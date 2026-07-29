import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/whatsapp.dart';

void main() {
  group('normalizePhone', () {
    test('local 0803 form becomes 234803…', () {
      expect(WhatsApp.normalizePhone('08031234567'), '2348031234567');
    });

    test('strips spaces, dashes and brackets', () {
      expect(WhatsApp.normalizePhone('0803 123-4567'), '2348031234567');
    });

    test('keeps an already international number', () {
      expect(WhatsApp.normalizePhone('+2348031234567'), '2348031234567');
    });

    test('handles 00 international prefix', () {
      expect(WhatsApp.normalizePhone('002348031234567'), '2348031234567');
    });

    test('adds country code to a bare 10-digit number', () {
      expect(WhatsApp.normalizePhone('8031234567'), '2348031234567');
    });

    test('null and empty are unusable', () {
      expect(WhatsApp.normalizePhone(null), isNull);
      expect(WhatsApp.normalizePhone('   '), isNull);
    });
  });

  test('debt reminder names the customer, amount and shop', () {
    final message = WhatsApp.debtReminder(
      customerName: 'Chidinma',
      amount: '₦12,500',
      businessName: "Nonny's Store",
    );

    expect(message, contains('Chidinma'));
    expect(message, contains('₦12,500'));
    expect(message, contains("Nonny's Store"));
  });
}
