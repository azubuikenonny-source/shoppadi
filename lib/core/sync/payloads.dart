import 'dart:convert';

import '../db/database.dart';

/// Turns local rows into the JSON Postgres expects.
///
/// Two rules run through all of it: money stays an integer (kobo → bigint, no
/// floats ever), and every row carries the business_id that RLS checks. A
/// mapper that forgets either one fails silently on the server, so each is
/// covered by a test.
class Payloads {
  static String? _iso(DateTime? value) => value?.toUtc().toIso8601String();

  /// Postgres `date` columns want a bare day, not a timestamp.
  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> product(Product row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'name': row.name,
        'sku': row.sku,
        'barcode': row.barcode,
        'category': row.category,
        'base_unit': row.baseUnit,
        'cost_price': row.costPrice,
        'selling_price': row.sellingPrice,
        'quantity': row.quantity,
        'low_stock_level': row.lowStockLevel,
        'vat_exempt': row.vatExempt,
        'is_active': row.isActive,
        'updated_at': _iso(row.updatedAt),
      };

  static Map<String, dynamic> customer(Customer row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'name': row.name,
        'phone': row.phone,
        'whatsapp_phone': row.whatsappPhone,
        'note': row.note,
        'updated_at': _iso(row.updatedAt),
      };

  static Map<String, dynamic> sale(Sale row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'customer_id': row.customerId,
        'receipt_no': row.receiptNo,
        'subtotal': row.subtotal,
        'discount': row.discount,
        'vat_amount': row.vatAmount,
        'total': row.total,
        'amount_paid': row.amountPaid,
        'payment_method': row.paymentMethod,
        'transfer_channel': row.transferChannel,
        'status': row.status,
        'sale_date': _date(row.saleDate),
      };

  static Map<String, dynamic> saleItem(SaleItem row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'sale_id': row.saleId,
        'product_id': row.productId,
        'unit_id': row.unitId,
        'qty': row.qty,
        'qty_base': row.qtyBase,
        'unit_price': row.unitPrice,
        'unit_cost_snapshot': row.unitCostSnapshot,
      };

  static Map<String, dynamic> payment(Payment row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'sale_id': row.saleId,
        'amount': row.amount,
        'method': row.method,
        'channel': row.channel,
        'provider': 'manual',
        'verified': false,
        'created_at': _iso(row.createdAt),
      };

  static Map<String, dynamic> stockMovement(
          StockMovement row, String businessId) =>
      {
        'id': row.id,
        'business_id': businessId,
        'product_id': row.productId,
        'type': row.type,
        'qty': row.qty,
        'unit_cost': row.unitCost,
        'note': row.note,
        'ref_sale_id': row.refSaleId,
        'created_at': _iso(row.createdAt),
      };

  static Map<String, dynamic> returnRow(Return row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'sale_id': row.saleId,
        // Already JSON text locally; send it as real JSON, not a quoted string.
        'items': jsonDecode(row.items),
        'restock': row.restock,
        'refund_method': row.refundMethod,
        'channel': row.channel,
        'amount': row.amount,
        'reason': row.reason,
        'created_at': _iso(row.createdAt),
      };

  static Map<String, dynamic> dayClose(DayClose row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'close_date': _date(row.closeDate),
        'expected_cash': row.expectedCash,
        'counted_cash': row.countedCash,
        'channel_totals': jsonDecode(row.channelTotals),
        'note': row.note,
        'created_at': _iso(row.createdAt),
      };

  static Map<String, dynamic> invoice(Invoice row, String businessId) => {
        'id': row.id,
        'business_id': businessId,
        'invoice_no': row.invoiceNo,
        'customer_id': row.customerId,
        'customer_name': row.customerName,
        'customer_phone': row.customerPhone,
        'items': jsonDecode(row.items),
        'subtotal': row.subtotal,
        'vat_amount': row.vatAmount,
        'total': row.total,
        'amount_paid': row.amountPaid,
        'issued_at': _iso(row.issuedAt),
        'due_date': row.dueDate == null ? null : _date(row.dueDate!),
        'status': row.status,
        'note': row.note,
        'sale_id': row.saleId,
        'updated_at': _iso(row.updatedAt),
      };
}
