import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database.dart';
import '../db/settings_repository.dart';
import 'hydrators.dart';
import 'payloads.dart';

/// How long to wait before retrying after [attempts] failures. Doubles up to a
/// ceiling so a shop with no signal all day does not hammer the radio flat.
Duration retryDelay(int attempts) {
  if (attempts <= 0) return Duration.zero;
  final seconds = 5 * (1 << (attempts - 1).clamp(0, 6));
  return Duration(seconds: seconds > 300 ? 300 : seconds);
}

/// An outbox row is abandoned after this many failures — usually it is a row
/// the server will never accept (deleted parent, RLS refusal), and retrying it
/// forever would block everything queued behind it.
const maxSyncAttempts = 8;

enum SyncPhase {
  idle,
  syncing,
  restoring,
  offline,
  error,
  notSignedIn,
  notConfigured,
}

class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.pending = 0,
    this.lastSyncedAt,
    this.restored = 0,
    this.message,
  });

  final SyncPhase phase;
  final int pending;
  final DateTime? lastSyncedAt;

  /// Rows brought down in the last pull — only interesting the first time,
  /// when a fresh phone is being repopulated.
  final int restored;
  final String? message;

  String get label => switch (phase) {
        SyncPhase.notConfigured => 'Cloud backup not set up',
        SyncPhase.notSignedIn => 'Sign in to back up',
        SyncPhase.syncing => 'Backing up…',
        SyncPhase.restoring => 'Bringing your records down…',
        SyncPhase.offline => pending == 0
            ? 'No connection'
            : '$pending waiting for signal',
        SyncPhase.error => message ?? 'Backup problem',
        SyncPhase.idle =>
          pending == 0 ? 'Everything backed up' : '$pending waiting',
      };
}

/// Moves records between local SQLite and Supabase (design doc §5).
///
/// Push drains the outbox: rows go up newest-state-wins by reading the current
/// local row at send time, so three edits to one product cost one request, not
/// three. Pull brings the shop back down onto a phone that has never seen it,
/// which is what makes a lost handset recoverable rather than merely archived.
class SyncEngine {
  SyncEngine({required this.db, required this.businessId});

  final AppDatabase db;

  /// Null until the shop has been created or joined on the server.
  final String? businessId;

  final _controller = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get status => _controller.stream;

  Timer? _timer;
  bool _running = false;
  DateTime? _lastSyncedAt;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null; // Supabase.initialize was never called
    }
  }

  void start({Duration every = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => syncNow());
    unawaited(syncNow());
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }

  Future<int> pendingCount() async {
    final rows = await db.select(db.outbox).get();
    return rows.length;
  }

  Future<SyncStatus> syncNow() async {
    if (_running) {
      return SyncStatus(phase: SyncPhase.syncing, pending: await pendingCount());
    }

    final client = _client;
    if (client == null) return _emit(const SyncStatus(phase: SyncPhase.notConfigured));
    if (client.auth.currentUser == null || businessId == null) {
      return _emit(SyncStatus(
          phase: SyncPhase.notSignedIn, pending: await pendingCount()));
    }

    _running = true;
    _emit(SyncStatus(phase: SyncPhase.syncing, pending: await pendingCount()));

    try {
      final now = DateTime.now();
      final due = await (db.select(db.outbox)
            ..orderBy([(o) => OrderingTerm(expression: o.seq)])
            ..limit(50))
          .get();

      for (final entry in due) {
        // Respect the backoff without blocking rows queued behind it.
        if (entry.attempts > 0 &&
            now.difference(entry.createdAt) < retryDelay(entry.attempts)) {
          continue;
        }

        try {
          await _push(client, entry);
          await (db.delete(db.outbox)..where((o) => o.seq.equals(entry.seq)))
              .go();
        } on Object catch (error) {
          final attempts = entry.attempts + 1;
          if (attempts >= maxSyncAttempts) {
            // Park it rather than block the queue forever.
            await (db.delete(db.outbox)..where((o) => o.seq.equals(entry.seq)))
                .go();
            _emit(SyncStatus(
              phase: SyncPhase.error,
              pending: await pendingCount(),
              message: 'A record could not be backed up: $error',
            ));
          } else {
            await (db.update(db.outbox)..where((o) => o.seq.equals(entry.seq)))
                .write(OutboxCompanion(
              attempts: Value(attempts),
              createdAt: Value(now),
            ));
          }
        }
      }

      // Pull after push, so anything typed on this phone is already upstream
      // before server rows come down and the dirty-row guard has less to skip.
      final stillPending = await pendingCount();
      if (stillPending == 0) {
        _emit(SyncStatus(phase: SyncPhase.restoring, pending: 0));
      }
      final restored = await _pull(client, businessId!);

      _lastSyncedAt = DateTime.now();
      return _emit(SyncStatus(
        phase: SyncPhase.idle,
        pending: await pendingCount(),
        lastSyncedAt: _lastSyncedAt,
        restored: restored,
      ));
    } on Object catch (error) {
      return _emit(SyncStatus(
        phase: isOfflineError(error) ? SyncPhase.offline : SyncPhase.error,
        pending: await pendingCount(),
        lastSyncedAt: _lastSyncedAt,
        message: isOfflineError(error) ? null : '$error',
      ));
    } finally {
      _running = false;
    }
  }

  SyncStatus _emit(SyncStatus status) {
    if (!_controller.isClosed) _controller.add(status);
    return status;
  }

  /// Sends one outbox entry. A sale is pushed as a whole aggregate — the sale,
  /// its lines, its payments and its stock movements — because they are written
  /// in one local transaction and only make sense together on the server.
  Future<void> _push(SupabaseClient client, OutboxData entry) async {
    final business = businessId!;

    switch (entry.targetTable) {
      case 'sales':
        await _pushSaleGraph(client, entry.rowId, business);

      case 'products':
        final row = await (db.select(db.products)
              ..where((p) => p.id.equals(entry.rowId)))
            .getSingleOrNull();
        if (row != null) {
          await client.from('products').upsert(Payloads.product(row, business));
        }

      case 'customers':
        final row = await (db.select(db.customers)
              ..where((c) => c.id.equals(entry.rowId)))
            .getSingleOrNull();
        if (row != null) {
          await client
              .from('customers')
              .upsert(Payloads.customer(row, business));
        }

      case 'returns':
        final row = await (db.select(db.returns)
              ..where((r) => r.id.equals(entry.rowId)))
            .getSingleOrNull();
        if (row != null) {
          await client
              .from('returns')
              .upsert(Payloads.returnRow(row, business));
          // The sale shrank when the goods came back, so re-send it.
          await _pushSaleGraph(client, row.saleId, business);
        }

      case 'day_closes':
        final row = await (db.select(db.dayCloses)
              ..where((c) => c.id.equals(entry.rowId)))
            .getSingleOrNull();
        if (row != null) {
          await client
              .from('day_closes')
              .upsert(Payloads.dayClose(row, business));
        }

      case 'invoices':
        final row = await (db.select(db.invoices)
              ..where((i) => i.id.equals(entry.rowId)))
            .getSingleOrNull();
        if (row != null) {
          await client.from('invoices').upsert(Payloads.invoice(row, business));
        }

      case 'app_settings':
        // rowId is the settings key, not a uuid. Only shop-level keys are ever
        // enqueued, but re-check here so a stale row can never leak a printer
        // MAC or a sync cursor to the server.
        final key = entry.rowId;
        if (!SettingsRepository.isShared(key)) return;
        final row = await (db.select(db.appSettings)
              ..where((s) => s.key.equals(key)))
            .getSingleOrNull();
        if (row == null) return;
        await client.from('app_settings').upsert({
          'business_id': business,
          'key': key,
          'value': row.value,
        });
        if (key == 'business_name' && row.value.trim().isNotEmpty) {
          // Best effort: businesses.name feeds restore and the staff invite
          // flow, but its update policy is owner-only — a manager editing the
          // footer must not wedge their sync queue on this.
          try {
            await client
                .from('businesses')
                .update({'name': row.value.trim()}).eq('id', business);
          } catch (_) {
            // The app_settings copy still made it; that is the one that syncs.
          }
        }

      default:
        // Unknown table: drop it rather than retry forever.
        return;
    }
  }

  /// Brings server rows down into local SQLite — what makes a lost phone
  /// recoverable rather than merely backed up.
  ///
  /// Tables are pulled parents-first so foreign keys always resolve, each from
  /// its own high-water mark so a repeat sync costs almost nothing. Rows with
  /// unsent local edits are skipped: the outbox is the record of what this
  /// phone changed and has not yet shared, and overwriting those would throw
  /// away a sale the shop just rang up.
  Future<int> _pull(SupabaseClient client, String business) async {
    final settings = SettingsRepository(db);
    final dirty = {
      for (final entry in await db.select(db.outbox).get()) entry.rowId,
    };
    var total = 0;

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'products',
      cursorColumn: 'updated_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.products, keep.map(Hydrators.product).toList()));
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'customers',
      cursorColumn: 'updated_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.customers, keep.map(Hydrators.customer).toList()));
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'sales',
      cursorColumn: 'updated_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        if (keep.isEmpty) return;

        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.sales, keep.map(Hydrators.sale).toList()));

        // Lines have no timestamp of their own and a return can delete one, so
        // each pulled sale's lines are replaced wholesale rather than merged.
        final saleIds = [for (final r in keep) r['id'] as String];
        final items = await client
            .from('sale_items')
            .select()
            .inFilter('sale_id', saleIds);

        await db.transaction(() async {
          await (db.delete(db.saleItems)
                ..where((i) => i.saleId.isIn(saleIds)))
              .go();
          await db.batch((b) => b.insertAllOnConflictUpdate(
                db.saleItems,
                items
                    .cast<Map<String, dynamic>>()
                    .map(Hydrators.saleItem)
                    .toList(),
              ));
        });
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'payments',
      cursorColumn: 'created_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.payments, keep.map(Hydrators.payment).toList()));
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'stock_movements',
      cursorColumn: 'created_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.stockMovements, keep.map(Hydrators.stockMovement).toList()));
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'returns',
      cursorColumn: 'created_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.returns, keep.map(Hydrators.returnRow).toList()));
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'day_closes',
      cursorColumn: 'created_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.dayCloses, keep.map(Hydrators.dayClose).toList()));
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'invoices',
      cursorColumn: 'updated_at',
      apply: (rows) async {
        final keep = rows.where((r) => !dirty.contains(r['id'])).toList();
        await db.batch((b) => b.insertAllOnConflictUpdate(
            db.invoices, keep.map(Hydrators.invoice).toList()));
      },
    );

    total += await _pullTable(
      client: client,
      business: business,
      settings: settings,
      table: 'app_settings',
      cursorColumn: 'updated_at',
      apply: (rows) async {
        for (final row in rows) {
          final key = row['key'] as String? ?? '';
          // Shared keys only, and never over an edit this phone has not sent
          // yet — the same dirty rule every other table follows.
          if (!SettingsRepository.isShared(key)) continue;
          if (dirty.contains(key)) continue;
          await db.into(db.appSettings).insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: key,
                  value: row['value'] as String? ?? '',
                ),
              );
        }
      },
    );

    // A restored phone should know the shop's name, not sit on "our shop".
    if (total > 0) {
      final shop = await client
          .from('businesses')
          .select('name')
          .eq('id', business)
          .maybeSingle();
      if (shop != null) {
        await settings.adoptShopNameIfBlank(shop['name'] as String? ?? '');
      }
    }

    return total;
  }

  static const _pageSize = 500;

  /// Pages one table down from its stored high-water mark and advances it.
  /// The cursor only moves after the rows are safely written, so an interrupted
  /// restore resumes rather than silently skipping the batch it dropped.
  Future<int> _pullTable({
    required SupabaseClient client,
    required String business,
    required SettingsRepository settings,
    required String table,
    required String cursorColumn,
    required Future<void> Function(List<Map<String, dynamic>>) apply,
  }) async {
    final since = await settings.pullCursor(table);
    var offset = 0;
    var pulled = 0;
    String? highWater;

    while (true) {
      var query =
          client.from(table).select().eq('business_id', business);
      if (since != null) query = query.gt(cursorColumn, since);

      final rows = await query
          .order(cursorColumn, ascending: true)
          .range(offset, offset + _pageSize - 1);

      if (rows.isEmpty) break;

      final batch = rows.cast<Map<String, dynamic>>();
      await apply(batch);
      pulled += batch.length;

      final last = batch.last[cursorColumn];
      if (last is String) highWater = last;

      if (batch.length < _pageSize) break;
      offset += _pageSize;
    }

    if (highWater != null) await settings.savePullCursor(table, highWater);
    return pulled;
  }

  Future<void> _pushSaleGraph(
      SupabaseClient client, String saleId, String business) async {
    final sale = await (db.select(db.sales)..where((s) => s.id.equals(saleId)))
        .getSingleOrNull();
    if (sale == null) return;

    await client.from('sales').upsert(Payloads.sale(sale, business));

    final items = await (db.select(db.saleItems)
          ..where((i) => i.saleId.equals(saleId)))
        .get();
    // Lines can disappear on a return, so the server copy is replaced wholesale.
    await client.from('sale_items').delete().eq('sale_id', saleId);
    if (items.isNotEmpty) {
      await client.from('sale_items').insert(
          [for (final item in items) Payloads.saleItem(item, business)]);
    }

    final payments = await (db.select(db.payments)
          ..where((p) => p.saleId.equals(saleId)))
        .get();
    if (payments.isNotEmpty) {
      await client.from('payments').upsert(
          [for (final p in payments) Payloads.payment(p, business)]);
    }

    final movements = await (db.select(db.stockMovements)
          ..where((m) => m.refSaleId.equals(saleId)))
        .get();
    if (movements.isNotEmpty) {
      await client.from('stock_movements').upsert(
          [for (final m in movements) Payloads.stockMovement(m, business)]);
    }
  }

}

/// "No signal" must not be reported as a backup failure — the whole point of
/// the outbox is that being offline is normal and harmless.
bool isOfflineError(Object error) {
  if (error is SocketException || error is HttpException) return true;
  final text = error.toString().toLowerCase();
  return text.contains('failed host lookup') ||
      text.contains('no address associated') ||
      text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('network is unreachable') ||
      text.contains('software caused connection abort');
}
