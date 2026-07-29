import 'package:url_launcher/url_launcher.dart';

/// WhatsApp sharing is the app's outbound channel (design doc 4.6): wa.me links
/// need no API, no Meta approval, and no per-message fee.
class WhatsApp {
  /// Nigerian numbers get typed as 0803…, 803…, or +234803… — wa.me needs
  /// the full international form with no punctuation.
  static String? normalizePhone(String? raw, {String countryCode = '234'}) {
    if (raw == null) return null;
    var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) return '$countryCode${digits.substring(1)}';
    if (digits.startsWith(countryCode)) return digits;
    if (digits.length <= 10) return '$countryCode$digits';
    return digits;
  }

  /// Opens WhatsApp with the message prefilled. Returns false when the phone
  /// is unusable or no handler is installed.
  static Future<bool> send({required String? phone, required String message}) async {
    final number = normalizePhone(phone);
    if (number == null) return false;
    final uri = Uri.parse(
        'https://wa.me/$number?text=${Uri.encodeComponent(message)}');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String debtReminder({
    required String customerName,
    required String amount,
    required String businessName,
  }) =>
      'Good day $customerName, this is a friendly reminder of your '
      'outstanding balance of $amount at $businessName. Thank you!';
}
