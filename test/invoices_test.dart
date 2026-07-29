import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/invoices_repository.dart';
import 'package:shoppadi/core/invoice_document.dart';
import 'package:shoppadi/core/money.dart';

const _items = [
  InvoiceItem(
      description: 'Rice 5kg', qty: 4, unitPrice: 1050000, productId: 'rice'),
  InvoiceItem(
      description: 'Sugar 1kg', qty: 2, unitPrice: 190000, productId: 'sugar'),
];

void main() {
  group('invoice totals', () {
    test('sum the lines when VAT is off', () {
      final totals = InvoiceTotals.of(_items);
      expect(totals.subtotal, 4580000); // 4×10,500 + 2×1,900
      expect(totals.vatAmount, 0);
      expect(totals.total, 4580000);
    });

    test('VAT is added on top, unlike a retail receipt', () {
      final totals = InvoiceTotals.of(_items, vatEnabled: true, vatRate: 7.5);
      expect(totals.subtotal, 4580000);
      expect(totals.vatAmount, 343500);
      expect(totals.total, 4923500);
    });

    test('an empty invoice totals zero', () {
      final totals = InvoiceTotals.of(const [], vatEnabled: true);
      expect(totals.total, 0);
      expect(totals.vatAmount, 0);
    });
  });

  group('invoice state', () {
    final today = DateTime(2026, 7, 25);

    test('a draft stays a draft even with a due date in the past', () {
      expect(
          invoiceStateOf(
              status: 'draft',
              total: 100000,
              amountPaid: 0,
              dueDate: DateTime(2026, 7, 1),
              now: today),
          InvoiceState.draft);
    });

    test('fully paid beats everything else', () {
      expect(
          invoiceStateOf(
              status: 'sent',
              total: 100000,
              amountPaid: 100000,
              dueDate: DateTime(2026, 7, 1),
              now: today),
          InvoiceState.paid);
    });

    test('past the due date and unpaid is overdue', () {
      expect(
          invoiceStateOf(
              status: 'sent',
              total: 100000,
              amountPaid: 0,
              dueDate: DateTime(2026, 7, 24),
              now: today),
          InvoiceState.overdue);
    });

    test('due today is not yet overdue', () {
      expect(
          invoiceStateOf(
              status: 'sent',
              total: 100000,
              amountPaid: 0,
              dueDate: today,
              now: today),
          InvoiceState.sent);
    });

    test('part paid and still in date reads as part paid', () {
      expect(
          invoiceStateOf(
              status: 'sent',
              total: 100000,
              amountPaid: 40000,
              dueDate: DateTime(2026, 8, 1),
              now: today),
          InvoiceState.partlyPaid);
    });

    test('overdue wins over part paid, because that is the actionable one', () {
      expect(
          invoiceStateOf(
              status: 'sent',
              total: 100000,
              amountPaid: 40000,
              dueDate: DateTime(2026, 7, 1),
              now: today),
          InvoiceState.overdue);
    });

    test('cancelled overrides even payment', () {
      expect(
          invoiceStateOf(
              status: 'cancelled',
              total: 100000,
              amountPaid: 100000,
              now: today),
          InvoiceState.cancelled);
    });
  });

  group('becoming a sale', () {
    String? blocker({
      String items = '[{"description":"Rice 5kg","qty":1,"unitPrice":1050000,"productId":"rice"}]',
      int total = 1050000,
      int amountPaid = 1050000,
      String? customerId = 'c1',
      String? saleId,
    }) =>
        conversionBlocker(
            itemsJson: items,
            total: total,
            amountPaid: amountPaid,
            customerId: customerId,
            saleId: saleId);

    test('a paid, catalogued invoice can convert', () {
      expect(blocker(), isNull);
    });

    test('converting twice is refused', () {
      expect(blocker(saleId: 'sale-1'), contains('Already recorded'));
    });

    test('typed-in lines cannot leave stock', () {
      expect(
          blocker(items: '[{"description":"Delivery","qty":1,"unitPrice":200000}]'),
          contains('free-typed'));
    });

    test('an unpaid invoice needs a customer to owe it', () {
      expect(blocker(amountPaid: 0, customerId: null), contains('owe it'));
      expect(blocker(amountPaid: 0), isNull); // customer present, fine
    });

    test('an empty invoice cannot convert', () {
      expect(blocker(items: '[]'), contains('Nothing'));
    });
  });

  group('invoice document', () {
    test('reference is stable and zero padded', () {
      expect(InvoiceDocument.reference(41, DateTime(2026, 7, 25)),
          'INV-2026-0041');
      expect(InvoiceDocument.fileName(7, DateTime(2026, 1, 3)),
          'INV-2026-0007.pdf');
    });

    test('PDF money spells out the currency, since ₦ has no glyph', () {
      expect(formatKoboAsCode(1050000), 'NGN 10,500.00');
      expect(formatKoboAsCode(50), 'NGN 0.50');
      expect(formatKoboAsCode(123456789), 'NGN 1,234,567.89');
    });
  });
}
