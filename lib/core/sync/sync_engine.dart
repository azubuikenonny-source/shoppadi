import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../db/database.dart';
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

enum SyncPhase { idle, syncing, offline, error, notSignedIn, notConfigured }

class SyncStatus {
  const SyncStatus({
    required this.phase,
    this.pending = 0,
    this.lastSyncedAt,
    this.message,
  });

  final SyncPhase phase;
  final int pending;
  final DateTime? lastSyncedAt;
  final String? message;

  String get label => switch (phase) {
        SyncPhase.notConfigured => 'Cloud backup not set up',
        SyncPhase.notSignedIn => 'Sign in to back up',
        SyncPhase.syncing => 'Backing up…',
        SyncPhase.offline => pending == 0
            ? 'No connection'
            : '$pending waiting for signal',
        SyncPhase.error => message ?? 'Backup problem',
        SyncPhase.idle =>
          pending == 0 ? 'Everything backed up' : '$pending waiting',
      };
}

/// Drains the outbox to Supabase (design doc §5).
///
/// Push only, for now: it is what makes a lost phone survivable. Rows are
/// pushed newest-state-wins by reading the current local row at send time, so
/// three edits to one product cost one request, not three.
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

      _lastSyncedAt = DateTime.now();
      return _emit(SyncStatus(
        phase: SyncPhase.idle,
        pending: await pendingCount(),
        lastSyncedAt: _lastSyncedAt,
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

      default:
        // Unknown table: drop it rather than retry forever.
        return;
    }
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
