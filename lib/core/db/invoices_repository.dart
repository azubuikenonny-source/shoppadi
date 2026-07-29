import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'sales_repository.dart';

const _uuid = Uuid();

/// One billed line. [productId] is set when the line came from the catalogue,
/// which is what later allows the invoice to become a real sale.
class InvoiceItem {
  const InvoiceItem({
    required this.description,
    required this.qty,
    required this.unitPrice,
    this.productId,
    this.costPerUnit,
  });

  final String description;
  final double qty;
  final int unitPrice; // kobo
  final String? productId;
  final int? costPerUnit; // kobo, needed to keep profit exact on conversion

  int get lineTotal => (qty * unitPrice).round();

  Map<String, dynamic> toJson() => {
        'description': description,
        'qty': qty,
        'unitPrice': unitPrice,
        if (productId != null) 'productId': productId,
        if (costPerUnit != null) 'costPerUnit': costPerUnit,
      };

  static InvoiceItem fromJson(Map<String, dynamic> json) => InvoiceItem(
        description: json['description'] as String? ?? 'Item',
        qty: (json['qty'] as num?)?.toDouble() ?? 1,
        unitPrice: (json['unitPrice'] as num?)?.toInt() ?? 0,
        productId: json['productId'] as String?,
        costPerUnit: (json['costPerUnit'] as num?)?.toInt(),
      );

  static List<InvoiceItem> decodeAll(String json) => [
        for (final entry in (jsonDecode(json) as List<dynamic>)
            .cast<Map<String, dynamic>>())
          fromJson(entry),
      ];

  static String encodeAll(List<InvoiceItem> items) =>
      jsonEncode([for (final item in items) item.toJson()]);
}

/// What the shop actually needs to see. Only draft / sent / cancelled are
/// stored — paid, part-paid and overdue are derived, so no background job is
/// needed to keep statuses honest as dates roll over.
enum InvoiceState { draft, sent, partlyPaid, overdue, paid, cancelled }

InvoiceState invoiceStateOf({
  required String status,
  required int total,
  required int amountPaid,
  DateTime? dueDate,
  DateTime? now,
}) {
  if (status == 'cancelled') return InvoiceState.cancelled;
  if (total > 0 && amountPaid >= total) return InvoiceState.paid;
  if (status == 'draft') return InvoiceState.draft;

  final today = now ?? DateTime.now();
  final startOfToday = DateTime(today.year, today.month, today.day);
  if (dueDate != null && dueDate.isBefore(startOfToday)) {
    return InvoiceState.overdue;
  }
  if (amountPaid > 0) return InvoiceState.partlyPaid;
  return InvoiceState.sent;
}

String invoiceStateLabel(InvoiceState state) => switch (state) {
      InvoiceState.draft => 'Draft',
      InvoiceState.sent => 'Sent',
      InvoiceState.partlyPaid => 'Part paid',
      InvoiceState.overdue => 'Overdue',
      InvoiceState.paid => 'Paid',
      InvoiceState.cancelled => 'Cancelled',
    };

/// Invoice totals. Unlike a retail receipt (where the shelf price already
/// includes VAT), an invoice adds VAT on top — that is what businesses expect
/// to receive and what they reclaim.
class InvoiceTotals {
  const InvoiceTotals({
    required this.subtotal,
    required this.vatAmount,
    required this.total,
  });

  final int subtotal;
  final int vatAmount;
  final int total;

  factory InvoiceTotals.of(
    List<InvoiceItem> items, {
    bool vatEnabled = false,
    double vatRate = 7.5,
  }) {
    final subtotal = items.fold<int>(0, (sum, item) => sum + item.lineTotal);
    final vat = vatEnabled ? (subtotal * vatRate / 100).round() : 0;
    return InvoiceTotals(
      subtotal: subtotal,
      vatAmount: vat,
      total: subtotal + vat,
    );
  }
}

/// Why this invoice cannot become a sale, or null when it can. Kept out of the
/// repository so the button can explain itself before anyone taps it.
String? conversionBlocker({
  required String itemsJson,
  required int total,
  required int amountPaid,
  String? customerId,
  String? saleId,
}) {
  if (saleId != null) return 'Already recorded as a sale.';
  final items = InvoiceItem.decodeAll(itemsJson);
  if (items.isEmpty) return 'Nothing on this invoice yet.';
  if (items.any((item) => item.productId == null)) {
    return 'Only invoices built from your products can become a sale — '
        'free-typed lines have no stock to take out.';
  }
  if (amountPaid < total && customerId == null) {
    return 'Choose a saved customer first: an unpaid sale needs someone to owe it.';
  }
  return null;
}

class InvoicesRepository {
  InvoicesRepository(this.db);

  final AppDatabase db;

  Stream<List<Invoice>> watchAll() => (db.select(db.invoices)
        ..orderBy([
          (i) => OrderingTerm(expression: i.issuedAt, mode: OrderingMode.desc),
          (i) => OrderingTerm(expression: i.invoiceNo, mode: OrderingMode.desc),
        ]))
      .watch();

  Stream<Invoice?> watch(String id) =>
      (db.select(db.invoices)..where((i) => i.id.equals(id)))
          .watchSingleOrNull();

  Future<String> create({
    required String customerName,
    String? customerId,
    String? customerPhone,
    required List<InvoiceItem> items,
    required bool vatEnabled,
    required double vatRate,
    DateTime? dueDate,
    String? note,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();
    final totals =
        InvoiceTotals.of(items, vatEnabled: vatEnabled, vatRate: vatRate);

    await db.transaction(() async {
      // TODO(sync): server-reserved ranges, same as receipt numbers (doc §5).
      final highest = await db
          .customSelect('SELECT COALESCE(MAX(invoice_no), 0) AS m FROM invoices')
          .getSingle();

      await db.into(db.invoices).insert(InvoicesCompanion.insert(
            id: id,
            invoiceNo: (highest.data['m'] as int) + 1,
            customerId: Value(customerId),
            customerName: customerName,
            customerPhone: Value(customerPhone),
            items: InvoiceItem.encodeAll(items),
            subtotal: totals.subtotal,
            vatAmount: Value(totals.vatAmount),
            total: totals.total,
            issuedAt: now,
            dueDate: Value(dueDate),
            note: Value(note == null || note.trim().isEmpty ? null : note.trim()),
            updatedAt: now,
          ));

      await db.into(db.outbox).insert(OutboxCompanion.insert(
            targetTable: 'invoices',
            rowId: id,
            op: 'insert',
            payload: '',
            createdAt: now,
          ));
    });

    return id;
  }

  Future<void> update({
    required String id,
    required String customerName,
    String? customerPhone,
    required List<InvoiceItem> items,
    required bool vatEnabled,
    required double vatRate,
    DateTime? dueDate,
    String? note,
  }) {
    final totals =
        InvoiceTotals.of(items, vatEnabled: vatEnabled, vatRate: vatRate);

    return (db.update(db.invoices)..where((i) => i.id.equals(id)))
        .write(InvoicesCompanion(
      customerName: Value(customerName),
      customerPhone: Value(customerPhone),
      items: Value(InvoiceItem.encodeAll(items)),
      subtotal: Value(totals.subtotal),
      vatAmount: Value(totals.vatAmount),
      total: Value(totals.total),
      dueDate: Value(dueDate),
      note: Value(note == null || note.trim().isEmpty ? null : note.trim()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// A draft becomes real the moment it is sent to the customer.
  Future<void> markSent(String id) =>
      (db.update(db.invoices)..where((i) => i.id.equals(id)))
          .write(InvoicesCompanion(
        status: const Value('sent'),
        updatedAt: Value(DateTime.now()),
      ));

  Future<void> cancel(String id) =>
      (db.update(db.invoices)..where((i) => i.id.equals(id)))
          .write(InvoicesCompanion(
        status: const Value('cancelled'),
        updatedAt: Value(DateTime.now()),
      ));

  Future<void> deleteDraft(String id) =>
      (db.delete(db.invoices)..where((i) => i.id.equals(id))).go();

  /// Records money against the invoice. Never records more than is owed.
  Future<void> recordPayment({required String id, required int amount}) async {
    final invoice = await (db.select(db.invoices)..where((i) => i.id.equals(id)))
        .getSingleOrNull();
    if (invoice == null || amount <= 0) return;

    final owing = invoice.total - invoice.amountPaid;
    final applied = amount > owing ? owing : amount;

    await (db.update(db.invoices)..where((i) => i.id.equals(id)))
        .write(InvoicesCompanion(
      amountPaid: Value(invoice.amountPaid + applied),
      status: Value(invoice.status == 'draft' ? 'sent' : invoice.status),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Turns a fully catalogued invoice into a real sale: stock comes down,
  /// revenue and profit appear, and the money lands in the payments ledger.
  /// This is the only path by which invoice money reaches the books, so it can
  /// never be double counted.
  ///
  /// Returns null when any line is free text (nothing to take out of stock).
  Future<String?> convertToSale(String id, SalesRepository sales) async {
    final invoice = await (db.select(db.invoices)..where((i) => i.id.equals(id)))
        .getSingleOrNull();
    if (invoice == null) return null;

    final blocked = conversionBlocker(
      itemsJson: invoice.items,
      total: invoice.total,
      amountPaid: invoice.amountPaid,
      customerId: invoice.customerId,
      saleId: invoice.saleId,
    );
    if (blocked != null) return null;

    final items = InvoiceItem.decodeAll(invoice.items);

    final result = await sales.recordSale(
      lines: [
        for (final item in items)
          CartLine(
            productId: item.productId!,
            qty: item.qty,
            unitPrice: item.unitPrice,
            costPerBase: item.costPerUnit ?? 0,
          ),
      ],
      paymentMethod: invoice.amountPaid >= invoice.total ? 'cash' : 'credit',
      customerId: invoice.customerId,
      amountPaidOverride: invoice.amountPaid,
    );

    await (db.update(db.invoices)..where((i) => i.id.equals(id)))
        .write(InvoicesCompanion(
      saleId: Value(result.saleId),
      updatedAt: Value(DateTime.now()),
    ));

    return result.saleId;
  }
}
