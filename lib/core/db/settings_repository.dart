import 'database.dart';
import 'outbox.dart';

/// The shop's own details — what prints on receipts and signs WhatsApp
/// messages. Wallet accounts are the "Transfer to:" line (design doc 7).
class ShopProfile {
  const ShopProfile({
    this.name = '',
    this.phone = '',
    this.receiptFooter = 'Thank you for your patronage!',
    this.accounts = const {},
    this.vatEnabled = false,
    this.vatRate = 7.5,
    this.printerMac,
    this.printerName,
    this.paperWidth = 32,
    this.autoPrint = false,
  });

  final String name;
  final String phone;
  final String receiptFooter;

  /// Off by default: most small shops are under the VAT threshold and should
  /// not be printing a tax line they do not owe.
  final bool vatEnabled;
  final double vatRate; // percent

  /// The paired Bluetooth printer, if one has been chosen.
  final String? printerMac;
  final String? printerName;
  final int paperWidth; // characters per line: 32 (58mm) or 48 (80mm)
  final bool autoPrint;

  bool get hasPrinter => (printerMac ?? '').isNotEmpty;

  /// channel key (opay | palmpay | moniepoint | bank) -> account number
  final Map<String, String> accounts;

  bool get isConfigured => name.trim().isNotEmpty;

  /// Falls back to a neutral phrase so messages never read "at ."
  String get displayName => name.trim().isEmpty ? 'our shop' : name.trim();
}

class SettingsRepository {
  SettingsRepository(this.db);

  final AppDatabase db;

  static const _name = 'business_name';
  static const _phone = 'business_phone';
  static const _footer = 'receipt_footer';
  static const _accountPrefix = 'account_';
  static const _vatEnabled = 'vat_enabled';
  static const _vatRate = 'vat_rate';
  static const _businessId = 'business_id';
  static const _printerMac = 'printer_mac';
  static const _printerName = 'printer_name';
  static const _paperWidth = 'paper_width';
  static const _autoPrint = 'auto_print';

  /// Which settings belong to the *shop* rather than this handset.
  ///
  /// Shop-level keys sync: the manager's receipts must carry the same name,
  /// footer and account numbers the owner typed, and a restored phone must get
  /// its receipt setup back. Everything else is deliberately local — a printer
  /// MAC pairs with one phone, sync cursors describe one phone's progress, and
  /// the cached role is one phone's permission. Syncing any of those would let
  /// one device corrupt another's state.
  static bool isShared(String key) =>
      key == _name ||
      key == _phone ||
      key == _footer ||
      key == _vatEnabled ||
      key == _vatRate ||
      key.startsWith(_accountPrefix);

  Stream<ShopProfile> watchProfile() =>
      db.select(db.appSettings).watch().map(_toProfile);

  Future<ShopProfile> load() async =>
      _toProfile(await db.select(db.appSettings).get());

  ShopProfile _toProfile(List<AppSetting> rows) {
    final map = {for (final r in rows) r.key: r.value};
    return ShopProfile(
      name: map[_name] ?? '',
      phone: map[_phone] ?? '',
      receiptFooter: map[_footer] ?? 'Thank you for your patronage!',
      accounts: {
        for (final entry in map.entries)
          if (entry.key.startsWith(_accountPrefix) && entry.value.isNotEmpty)
            entry.key.substring(_accountPrefix.length): entry.value,
      },
      vatEnabled: map[_vatEnabled] == 'true',
      vatRate: double.tryParse(map[_vatRate] ?? '') ?? 7.5,
      printerMac: map[_printerMac],
      printerName: map[_printerName],
      paperWidth: int.tryParse(map[_paperWidth] ?? '') ?? 32,
      autoPrint: map[_autoPrint] == 'true',
    );
  }

  /// The shop's server id, cached after the first sign-in.
  Future<String?> businessId() async {
    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals(_businessId)))
        .getSingleOrNull();
    final value = row?.value ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> saveBusinessId(String id) => _put(_businessId, id);

  /// How far each table has been pulled from the server, as the server's own
  /// timestamp. Kept as settings rather than a table of their own so that
  /// "Erase all data" clears them too — a wiped phone must re-pull everything
  /// rather than think it is already up to date.
  static const _cursorPrefix = 'sync_cursor_';

  Future<String?> pullCursor(String table) async {
    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals('$_cursorPrefix$table')))
        .getSingleOrNull();
    final value = row?.value ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> savePullCursor(String table, String isoTimestamp) =>
      _put('$_cursorPrefix$table', isoTimestamp);

  /// The role is cached because permissions have to hold with no signal. A
  /// cashier on a market street with no data must still be a cashier, not
  /// briefly promoted to owner because the app could not ask.
  static const _role = 'member_role';
  static const _seesProfit = 'member_sees_profit';

  Future<void> saveMembership(String role, bool canSeeProfit) async {
    await _put(_role, role);
    await _put(_seesProfit, canSeeProfit.toString());
  }

  Future<(String?, bool)> cachedMembership() async {
    final rows = await db.select(db.appSettings).get();
    final map = {for (final r in rows) r.key: r.value};
    final role = map[_role];
    return (
      role == null || role.isEmpty ? null : role,
      map[_seesProfit] == 'true',
    );
  }

  /// Restoring onto a fresh phone should bring the shop's name with it, but
  /// never overwrite a name the owner has already typed on this device.
  Future<void> adoptShopNameIfBlank(String name) async {
    if (name.trim().isEmpty) return;
    final current = await load();
    if (current.name.trim().isNotEmpty) return;
    await _put(_name, name.trim());
  }

  Future<void> savePrinter({
    String? mac,
    String? name,
    required int paperWidth,
    required bool autoPrint,
  }) async {
    await _put(_printerMac, mac ?? '');
    await _put(_printerName, name ?? '');
    await _put(_paperWidth, paperWidth.toString());
    await _put(_autoPrint, autoPrint.toString());
  }

  Future<void> saveVat({required bool enabled, required double rate}) async {
    await _put(_vatEnabled, enabled.toString());
    await _put(_vatRate, rate.toString());
    await _enqueueShared([_vatEnabled, _vatRate]);
  }

  /// Queues shop-level settings for the server. Kept out of [_put] on purpose:
  /// _put also writes sync cursors, and a cursor save that enqueued itself
  /// would make every sync schedule the next one forever.
  Future<void> _enqueueShared(List<String> keys) async {
    for (final key in keys.where(isShared)) {
      await enqueue(db, 'app_settings', key);
    }
  }

  Future<void> saveProfile({
    required String name,
    required String phone,
    required String receiptFooter,
    required Map<String, String> accounts,
  }) async {
    await db.transaction(() async {
      await _put(_name, name);
      await _put(_phone, phone);
      await _put(_footer, receiptFooter);
      for (final entry in accounts.entries) {
        await _put('$_accountPrefix${entry.key}', entry.value);
      }
      await _enqueueShared([
        _name,
        _phone,
        _footer,
        for (final key in accounts.keys) '$_accountPrefix$key',
      ]);
    });
  }

  Future<void> _put(String key, String value) =>
      db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: key, value: value),
          );
}
