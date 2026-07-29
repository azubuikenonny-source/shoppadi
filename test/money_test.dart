import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/money.dart';

void main() {
  group('formatKobo', () {
    test('formats kobo with decimals', () {
      expect(formatKobo(1250050), '₦12,500.50');
    });

    test('zero', () {
      expect(formatKobo(0), '₦0.00');
    });
  });

  group('formatKoboCompact', () {
    test('drops .00 on whole naira', () {
      expect(formatKoboCompact(1250000), '₦12,500');
    });

    test('keeps decimals when not whole', () {
      expect(formatKoboCompact(1250050), '₦12,500.50');
    });
  });

  group('parseNairaToKobo', () {
    test('plain number', () {
      expect(parseNairaToKobo('12500.50'), 1250050);
    });

    test('with symbol and commas', () {
      expect(parseNairaToKobo('₦12,500'), 1250000);
    });

    test('garbage returns null', () {
      expect(parseNairaToKobo('abc'), null);
    });

    test('negative rejected', () {
      expect(parseNairaToKobo('-50'), null);
    });

    test('avoids float truncation', () {
      // naive (19.99 * 100).toInt() gives 1998 — round() must win
      expect(parseNairaToKobo('19.99'), 1999);
    });
  });
}
