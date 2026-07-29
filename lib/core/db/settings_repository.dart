import 'database.dart';

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
    });
  }

  Future<void> _put(String key, String value) =>
      db.into(db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(key: key, value: value),
          );
}
