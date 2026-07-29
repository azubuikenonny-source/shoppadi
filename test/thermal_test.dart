import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/settings_repository.dart';
import 'package:shoppadi/core/money.dart';
import 'package:shoppadi/core/printing/escpos.dart';
import 'package:shoppadi/core/printing/thermal_receipt.dart';
import 'package:shoppadi/core/receipt.dart';

const _shop = ShopProfile(
  name: "Nonny's Store",
  phone: '08031234567',
  receiptFooter: 'Thank you! No refund after 7 days.',
  accounts: {'moniepoint': '1234567890'},
);

void main() {
  group('column layout', () {
    test('label left, amount right, filling the paper exactly', () {
      final line = ThermalReceipt.row('TOTAL', 'NGN 1,800.00', 32);
      expect(line.length, 32);
      expect(line.startsWith('TOTAL'), isTrue);
      expect(line.endsWith('NGN 1,800.00'), isTrue);
    });

    test('a long product name is cut, never the amount', () {
      final line = ThermalReceipt.row(
          'Golden Penny Semovita 1kg premium', '10,500.00', 32);
      expect(line.length, 32);
      expect(line.endsWith('10,500.00'), isTrue);
    });

    test('80mm paper uses the extra width', () {
      final line = ThermalReceipt.row('TOTAL', '1,800.00', 48);
      expect(line.length, 48);
    });

    test('centring never overflows the paper', () {
      expect(ThermalReceipt.centre('SHOP', 32).length, lessThanOrEqualTo(32));
      expect(
          ThermalReceipt.centre('A' * 40, 32).length, 32); // truncated, not wrapped
    });
  });

  group('receipt layout', () {
    List<String> lines({int width = 32, int paid = 300000}) =>
        ThermalReceipt.layout(
          shop: _shop,
          receiptNo: 41,
          items: const [
            ReceiptLine(name: 'Peak Milk sachet', qty: 2, lineTotal: 80000),
            ReceiptLine(
                name: 'Golden Penny Semovita 1kg', qty: 1, lineTotal: 220000),
          ],
          total: 300000,
          amountPaid: paid,
          at: DateTime(2026, 7, 25, 10, 47),
          width: width,
        );

    test('no line is wider than the paper', () {
      for (final width in PaperWidth.all) {
        for (final line in lines(width: width)) {
          expect(line.length, lessThanOrEqualTo(width),
              reason: 'overflowed at ${width}c: "$line"');
        }
      }
    });

    test('never prints the naira sign, which printers cannot render', () {
      expect(lines().join('\n'), isNot(contains('₦')));
      expect(lines().any((l) => l.contains('NGN')), isTrue);
    });

    test('a fully paid receipt shows no balance and no account numbers', () {
      final printed = lines().join('\n');
      expect(printed, isNot(contains('BALANCE DUE')));
      expect(printed, isNot(contains('1234567890')));
    });

    test('a part-paid receipt shows the balance and where to send it', () {
      final printed = lines(paid: 100000).join('\n');
      expect(printed, contains('BALANCE DUE'));
      expect(printed, contains('2,000.00'));
      expect(printed, contains('Moniepoint: 1234567890'));
    });

    test('the shop name and footer make it onto the paper', () {
      final printed = lines().join('\n');
      expect(printed, contains("NONNY'S STORE"));
      expect(printed, contains('Receipt #41'));
      expect(printed, contains('refund'));
    });
  });

  group('escpos bytes', () {
    test('starts by resetting the printer', () {
      final bytes = EscPos().init().build();
      expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    });

    test('a finished receipt ends with a cut', () {
      final bytes = ThermalReceipt.bytes(
        shop: _shop,
        receiptNo: 1,
        items: const [ReceiptLine(name: 'Test', qty: 1, lineTotal: 100000)],
        total: 100000,
        amountPaid: 100000,
      );
      expect(bytes.sublist(bytes.length - 3), [0x1D, 0x56, 0x01]);
    });

    test('text is encoded one byte per character', () {
      final bytes = EscPos().line('AB').build();
      expect(bytes, [0x41, 0x42, 0x0A]);
    });

    test('naira becomes NGN rather than a mystery glyph', () {
      expect(EscPos.sanitize('₦1,500'), 'NGN1,500');
    });

    test('smart quotes and dashes are flattened, emoji dropped', () {
      expect(EscPos.sanitize('Thank you — “boss”'), 'Thank you - "boss"');
      expect(EscPos.sanitize('Nice 👍'), 'Nice ');
    });

    test('every byte is printable by an 8-bit printer', () {
      final bytes = ThermalReceipt.bytes(
        shop: _shop,
        receiptNo: 41,
        items: const [
          ReceiptLine(name: 'Peak Milk sachet', qty: 2, lineTotal: 80000)
        ],
        total: 80000,
        amountPaid: 40000,
      );
      expect(bytes.every((b) => b >= 0 && b <= 255), isTrue);
    });
  });

  group('plain money for paper', () {
    test('drops the symbol but keeps the grouping', () {
      expect(formatKoboPlain(1050000), '10,500.00');
      expect(formatKoboPlain(50), '0.50');
      expect(formatKoboPlain(123456789), '1,234,567.89');
    });
  });
}
