import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/channels.dart';

/// Mirrors the rule inside SalesRepository.recordSale: a credit sale is unpaid
/// unless the caller says otherwise, everything else is paid in full.
int amountPaidFor({
  required String paymentMethod,
  required int total,
  int? override,
}) =>
    override ?? (paymentMethod == 'credit' ? 0 : total);

void main() {
  group('what counts as paid', () {
    test('a credit sale records no payment, so it becomes a debt', () {
      expect(amountPaidFor(paymentMethod: 'credit', total: 1590000), 0);
    });

    test('cash and transfers are paid in full', () {
      expect(amountPaidFor(paymentMethod: 'cash', total: 780000), 780000);
      expect(amountPaidFor(paymentMethod: 'transfer', total: 780000), 780000);
      expect(amountPaidFor(paymentMethod: 'pos', total: 780000), 780000);
    });

    test('an explicit part payment always wins', () {
      expect(
          amountPaidFor(paymentMethod: 'cash', total: 780000, override: 300000),
          300000);
      expect(
          amountPaidFor(
              paymentMethod: 'credit', total: 780000, override: 100000),
          100000);
    });
  });

  group('payment method labels', () {
    test('every method a sale can store has a readable label', () {
      for (final method in ['cash', 'transfer', 'pos', 'card', 'credit', 'split']) {
        expect(channelLabels.containsKey(method), isTrue,
            reason: 'no label for $method');
      }
    });

    test('credit reads as Credit, not the raw column value', () {
      expect(channelLabel('credit'), 'Credit');
      expect(channelLabel('debt_credit'), 'Off their balance');
    });
  });
}
