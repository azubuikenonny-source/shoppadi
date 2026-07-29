import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/settings_repository.dart';
import 'package:shoppadi/core/receipt.dart';

const _shop = ShopProfile(
  name: "Nonny's Store",
  phone: '08031234567',
  receiptFooter: 'No refund after 7 days',
  accounts: {'moniepoint': '1234567890'},
);

final _lines = [
  const ReceiptLine(name: 'Peak Milk', qty: 2, lineTotal: 300000),
  const ReceiptLine(name: 'Bread', qty: 1, lineTotal: 90000),
];

void main() {
  test('paid-in-full receipt shows no balance and no account details', () {
    final text = Receipt.build(
      shop: _shop,
      receiptNo: 41,
      lines: _lines,
      total: 390000,
      amountPaid: 390000,
      at: DateTime(2026, 7, 25, 14, 30),
    );

    expect(text, contains("NONNY'S STORE"));
    expect(text, contains('Receipt #41'));
    expect(text, contains('2 x Peak Milk'));
    expect(text, contains('₦3,900'));
    expect(text, isNot(contains('BALANCE DUE')));
    expect(text, isNot(contains('1234567890')));
    expect(text, contains('No refund after 7 days'));
  });

  test('part-paid receipt shows the balance and how to pay it', () {
    final text = Receipt.build(
      shop: _shop,
      receiptNo: 42,
      lines: _lines,
      total: 390000,
      amountPaid: 150000,
      customerName: 'Chidinma',
      at: DateTime(2026, 7, 25, 14, 30),
    );

    expect(text, contains('Customer: Chidinma'));
    expect(text, contains('BALANCE DUE: ₦2,400'));
    expect(text, contains('Moniepoint: 1234567890'));
  });

  test('unconfigured shop still produces a usable receipt', () {
    final text = Receipt.build(
      shop: const ShopProfile(),
      receiptNo: 1,
      lines: _lines,
      total: 390000,
      amountPaid: 390000,
      at: DateTime(2026, 7, 25),
    );

    expect(text, contains('OUR SHOP'));
    expect(text, contains('₦3,900'));
  });
}
