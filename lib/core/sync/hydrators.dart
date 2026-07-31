import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/database.dart';

/// The inverse of [Payloads]: server JSON back into local rows.
///
/// Every reader is defensive about type. Postgres `numeric` arrives as int or
/// double depending on the value, `bigint` can arrive as either in JSON, and a
/// column added by a later migration is simply absent on older rows. A cast
/// that assumes one shape crashes a restore halfway through and leaves the
/// shop with a torn copy of its own books.
class Hydrators {
  static int _int(Object? v, [int fallback = 0]) =>
      v is num ? v.toInt() : fallback;

  static double _double(Object? v, [double fallback = 0]) =>
      v is num ? v.toDouble() : fallback;

  static String _text(Object? v, [String fallback = '']) =>
      v is String ? v : fallback;

  static String? _maybeText(Object? v) => v is String && v.isNotEmpty ? v : null;

  static bool _bool(Object? v, [bool fallback = false]) =>
      v is bool ? v : fallback;

  /// Timestamps come back as UTC ISO strings; the app works in local time.
  static DateTime _time(Object? v, [DateTime? fallback]) {
    if (v is String) {
      final parsed = DateTime.tryParse(v);
      if (parsed != null) return parsed.toLocal();
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// A `date` column is a bare day — parsing it as a timestamp would drag it
  /// across midnight in either direction depending on the timezone.
  static DateTime _day(Object? v, [DateTime? fallback]) {
    if (v is String && v.length >= 10) {
      final year = int.tryParse(v.substring(0, 4));
      final month = int.tryParse(v.substring(5, 7));
      final day = int.tryParse(v.substring(8, 10));
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  /// jsonb arrives decoded; local columns hold it as text.
  static String _json(Object? v, String fallback) =>
      v == null ? fallback : jsonEncode(v);

  static ProductsCompanion product(Map<String, dynamic> row) =>
      ProductsCompanion(
        id: Value(_text(row['id'])),
        name: Value(_text(row['name'])),
        sku: Value(_maybeText(row['sku'])),
        barcode: Value(_maybeText(row['barcode'])),
        category: Value(_maybeText(row['category'])),
        baseUnit: Value(_text(row['base_unit'], 'piece')),
        costPrice: Value(_int(row['cost_price'])),
        sellingPrice: Value(_int(row['selling_price'])),
        quantity: Value(_double(row['quantity'])),
        lowStockLevel: Value(_double(row['low_stock_level'])),
        vatExempt: Value(_bool(row['vat_exempt'])),
        isActive: Value(_bool(row['is_active'], true)),
        updatedAt: Value(_time(row['updated_at'], DateTime.now())),
      );

  static CustomersCompanion customer(Map<String, dynamic> row) =>
      CustomersCompanion(
        id: Value(_text(row['id'])),
        name: Value(_text(row['name'])),
        phone: Value(_maybeText(row['phone'])),
        whatsappPhone: Value(_maybeText(row['whatsapp_phone'])),
        note: Value(_maybeText(row['note'])),
        updatedAt: Value(_time(row['updated_at'], DateTime.now())),
      );

  static SalesCompanion sale(Map<String, dynamic> row) => SalesCompanion(
        id: Value(_text(row['id'])),
        customerId: Value(_maybeText(row['customer_id'])),
        receiptNo: Value(_int(row['receipt_no'])),
        subtotal: Value(_int(row['subtotal'])),
        discount: Value(_int(row['discount'])),
        vatAmount: Value(_int(row['vat_amount'])),
        total: Value(_int(row['total'])),
        amountPaid: Value(_int(row['amount_paid'])),
        paymentMethod: Value(_text(row['payment_method'], 'cash')),
        transferChannel: Value(_maybeText(row['transfer_channel'])),
        status: Value(_text(row['status'], 'completed')),
        saleDate: Value(_day(row['sale_date'], DateTime.now())),
      );

  static SaleItemsCompanion saleItem(Map<String, dynamic> row) =>
      SaleItemsCompanion(
        id: Value(_text(row['id'])),
        saleId: Value(_text(row['sale_id'])),
        productId: Value(_text(row['product_id'])),
        unitId: Value(_maybeText(row['unit_id'])),
        qty: Value(_double(row['qty'])),
        qtyBase: Value(_double(row['qty_base'])),
        unitPrice: Value(_int(row['unit_price'])),
        unitCostSnapshot: Value(_int(row['unit_cost_snapshot'])),
      );

  static PaymentsCompanion payment(Map<String, dynamic> row) =>
      PaymentsCompanion(
        id: Value(_text(row['id'])),
        saleId: Value(_maybeText(row['sale_id'])),
        amount: Value(_int(row['amount'])),
        method: Value(_text(row['method'], 'cash')),
        channel: Value(_maybeText(row['channel'])),
        createdAt: Value(_time(row['created_at'], DateTime.now())),
      );

  static StockMovementsCompanion stockMovement(Map<String, dynamic> row) =>
      StockMovementsCompanion(
        id: Value(_text(row['id'])),
        productId: Value(_text(row['product_id'])),
        type: Value(_text(row['type'], 'adjustment')),
        qty: Value(_double(row['qty'])),
        unitCost:
            Value(row['unit_cost'] is num ? _int(row['unit_cost']) : null),
        note: Value(_maybeText(row['note'])),
        refSaleId: Value(_maybeText(row['ref_sale_id'])),
        createdAt: Value(_time(row['created_at'], DateTime.now())),
      );

  static ReturnsCompanion returnRow(Map<String, dynamic> row) =>
      ReturnsCompanion(
        id: Value(_text(row['id'])),
        saleId: Value(_text(row['sale_id'])),
        items: Value(_json(row['items'], '[]')),
        restock: Value(_bool(row['restock'], true)),
        refundMethod: Value(_text(row['refund_method'], 'cash')),
        channel: Value(_maybeText(row['channel'])),
        amount: Value(_int(row['amount'])),
        reason: Value(_maybeText(row['reason'])),
        createdAt: Value(_time(row['created_at'], DateTime.now())),
      );

  static DayClosesCompanion dayClose(Map<String, dynamic> row) =>
      DayClosesCompanion(
        id: Value(_text(row['id'])),
        closeDate: Value(_day(row['close_date'], DateTime.now())),
        expectedCash: Value(_int(row['expected_cash'])),
        countedCash: Value(_int(row['counted_cash'])),
        channelTotals: Value(_json(row['channel_totals'], '{}')),
        note: Value(_maybeText(row['note'])),
        createdAt: Value(_time(row['created_at'], DateTime.now())),
      );

  static InvoicesCompanion invoice(Map<String, dynamic> row) =>
      InvoicesCompanion(
        id: Value(_text(row['id'])),
        invoiceNo: Value(_int(row['invoice_no'])),
        customerId: Value(_maybeText(row['customer_id'])),
        customerName: Value(_text(row['customer_name'])),
        customerPhone: Value(_maybeText(row['customer_phone'])),
        items: Value(_json(row['items'], '[]')),
        subtotal: Value(_int(row['subtotal'])),
        vatAmount: Value(_int(row['vat_amount'])),
        total: Value(_int(row['total'])),
        amountPaid: Value(_int(row['amount_paid'])),
        issuedAt: Value(_time(row['issued_at'], DateTime.now())),
        dueDate: Value(row['due_date'] == null ? null : _day(row['due_date'])),
        status: Value(_text(row['status'], 'draft')),
        note: Value(_maybeText(row['note'])),
        saleId: Value(_maybeText(row['sale_id'])),
        updatedAt: Value(_time(row['updated_at'], DateTime.now())),
      );
}
