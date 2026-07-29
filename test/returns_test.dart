import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/returns_repository.dart';

void main() {
  group('a plain sale, no discount or VAT', () {
    // Two items at ₦2,200 plus one at ₦3,400 = ₦7,800.
    ReturnMaths returning(int gross) => ReturnMaths.from(
          oldSubtotal: 780000,
          oldDiscount: 0,
          oldVat: 0,
          oldTotal: 780000,
          returnedGross: gross,
        );

    test('returning one ₦2,200 item refunds exactly that', () {
      final maths = returning(220000);
      expect(maths.refund, 220000);
      expect(maths.total, 560000);
      expect(maths.subtotal, 560000);
    });

    test('returning everything empties the sale', () {
      final maths = returning(780000);
      expect(maths.refund, 780000);
      expect(maths.total, 0);
    });

    test('returning nothing changes nothing', () {
      final maths = returning(0);
      expect(maths.refund, 0);
      expect(maths.total, 780000);
    });
  });

  group('a discounted sale', () {
    // ₦10,000 of goods with ₦1,000 off — the customer paid ₦9,000.
    test('refund is scaled to what the customer actually paid', () {
      final maths = ReturnMaths.from(
        oldSubtotal: 1000000,
        oldDiscount: 100000,
        oldVat: 0,
        oldTotal: 900000,
        returnedGross: 500000, // half the goods
      );

      // Half the goods came back, so half of the discounted price goes back —
      // not the full ₦5,000 sticker value.
      expect(maths.refund, 450000);
      expect(maths.subtotal, 500000);
      expect(maths.discount, 50000);
      expect(maths.total, 450000);
    });

    test('a full return gives back the discounted total, never the sticker', () {
      final maths = ReturnMaths.from(
        oldSubtotal: 1000000,
        oldDiscount: 100000,
        oldVat: 0,
        oldTotal: 900000,
        returnedGross: 1000000,
      );
      expect(maths.refund, 900000);
      expect(maths.total, 0);
      expect(maths.discount, 0);
    });
  });

  group('a VAT-inclusive sale', () {
    test('VAT shrinks with the goods', () {
      final maths = ReturnMaths.from(
        oldSubtotal: 1075000,
        oldDiscount: 0,
        oldVat: 75000,
        oldTotal: 1075000,
        returnedGross: 537500, // half
      );
      expect(maths.vatAmount, 37500);
      expect(maths.refund, 537500);
    });
  });

  group('stored return items', () {
    test('decode back into names and quantities', () {
      final items = ReturnedItem.decodeAll(
          '[{"name":"Peak Milk sachet","qty":2,"value":80000},'
          '{"name":"Rice 5kg","qty":1,"value":1050000}]');

      expect(items, hasLength(2));
      expect(items.first.name, 'Peak Milk sachet');
      expect(items.first.qty, 2);
      expect(items.first.value, 80000);
      expect(items.last.name, 'Rice 5kg');
    });

    test('a missing name falls back rather than crashing', () {
      final items = ReturnedItem.decodeAll('[{"qty":1,"value":5000}]');
      expect(items.single.name, 'Item');
    });
  });
}
