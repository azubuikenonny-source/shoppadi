import 'package:intl/intl.dart';

/// All money in ShopPadi is integer kobo. These helpers are the only place
/// kobo becomes a display string — never format naira anywhere else.
final NumberFormat _naira = NumberFormat.currency(
  locale: 'en_NG',
  symbol: '₦',
  decimalDigits: 2,
);

final NumberFormat _nairaWhole = NumberFormat.currency(
  locale: 'en_NG',
  symbol: '₦',
  decimalDigits: 0,
);

/// 1250050 kobo -> "₦12,500.50"
String formatKobo(int kobo) => _naira.format(kobo / 100);

/// 1250000 kobo -> "₦12,500" (receipts, dashboards — drops .00 when whole)
String formatKoboCompact(int kobo) =>
    kobo % 100 == 0 ? _nairaWhole.format(kobo ~/ 100) : formatKobo(kobo);

/// 1250050 kobo -> "12,500.50". No symbol at all — for thermal receipts and
/// PDF tables where the column header already says what the currency is.
String formatKoboPlain(int kobo) {
  final naira = (kobo / 100).toStringAsFixed(2);
  final parts = naira.split('.');
  final withCommas = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return '$withCommas.${parts[1]}';
}

/// 1250050 kobo -> "NGN 12,500.50". The ₦ glyph is missing from the standard
/// PDF fonts, so documents spell the currency out instead of printing a box.
String formatKoboAsCode(int kobo) {
  final naira = (kobo / 100).toStringAsFixed(2);
  final parts = naira.split('.');
  final withCommas = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
  return 'NGN $withCommas.${parts[1]}';
}

/// "12500.50" (user input in naira) -> 1250050 kobo. Null if unparseable.
int? parseNairaToKobo(String input) {
  final cleaned = input.replaceAll(RegExp(r'[₦,\s]'), '');
  if (cleaned.isEmpty) return null;
  final value = double.tryParse(cleaned);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}
