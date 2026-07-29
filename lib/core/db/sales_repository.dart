import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

const _uuid = Uuid();

/// One line in the cart. [factorToBase] is 1 for the base unit;
/// for pack units it comes from product_units.factor_to_base.
class CartLine {
  CartLine({
    required this.productId,
    required this.qty,
    required this.unitPrice,
    required this.costPerBase,
    this.unitId,
    this.factorToBase = 1,
    this.vatExempt = false,
  });

  final String productId;
  final String? unitId;
  final double qty;
  final double factorToBase;
  final int unitPrice; // kobo, per sold unit
  final int costPerBase; // kobo, per base unit (COGS snapshot)
  final bool vatExempt;

  double get qtyBase => qty * factorToBase;
  int get lineTotal => (qty * unitPrice).round();
}

class CheckoutResult {
  CheckoutResult({required this.saleId, required this.receiptNo});
  final String saleId;
  final int receiptNo;
}

/// A sale plus the customer's name, for the receipts list.
class SaleSummary {
  const SaleSummary({required this.sale, this.customerName});

  final Sale sale;
  final String? customerName;

  int get balance => sale.total - sale.amountPaid;
}

class SalesRepository {
  SalesRepository(this.db);

  final AppDatabase db;

  /// Newest receipts first — the list you search when a customer walks back in.
  Stream<List<SaleSummary>> watchRecentSales({int limit = 200}) {
    final query = db.select(db.sales).join([
      leftOuterJoin(
          db.customers, db.customers.id.equalsExp(db.sales.customerId)),
    ])
      ..orderBy([
        OrderingTerm(expression: db.sales.saleDate, mode: OrderingMode.desc),
        OrderingTerm(expression: db.sales.receiptNo, mode: OrderingMode.desc),
      ])
      ..limit(limit);

    return query.watch().map((rows) => [
          for (final row in rows)
            SaleSummary(
              sale: row.readTable(db.sales),
              customerName: row.readTableOrNull(db.customers)?.name,
            ),
        ]);
  }

  /// Records a sale atomically: sale + items + stock movements + payment +
  /// outbox rows, in one local transaction (design doc 4.1). Sync pushes the
  /// outbox later; ids are client UUIDs so replays are idempotent.
  ///
  /// [amountPaid] < total requires [customerId] — the remainder is debt.
  /// [vatRate] is percent (7.5) and only applied when [vatEnabled].
  Future<CheckoutResult> recordSale({
    required List<CartLine> lines,
    required String paymentMethod, // cash|transfer|pos|card|credit|split
    String? transferChannel, // opay|palmpay|moniepoint|bank|other
    String? customerId,
    int discount = 0,
    int? amountPaidOverride,
    bool vatEnabled = false,
    double vatRate = 7.5,
    DateTime? at,
  }) async {
    assert(lines.isNotEmpty, 'cannot record an empty sale');

    final subtotal = lines.fold<int>(0, (sum, l) => sum + l.lineTotal);
    final vatable = vatEnabled
        ? lines.where((l) => !l.vatExempt).fold<int>(0, (s, l) => s + l.lineTotal)
        : 0;
    // VAT-inclusive pricing (Nigerian retail convention): extract, don't add.
    final vatAmount =
        vatable == 0 ? 0 : (vatable - vatable / (1 + vatRate / 100)).round();
    final total = subtotal - discount;
    // "Credit" means they have not paid — anything else defaults to paid in
    // full. Without this, a credit sale would silently record no debt.
    final amountPaid =
        amountPaidOverride ?? (paymentMethod == 'credit' ? 0 : total);

    if (amountPaid < total && customerId == null) {
      throw ArgumentError('credit/partial sale requires a customer');
    }

    final saleId = _uuid.v4();
    final now = at ?? DateTime.now();

    return db.transaction(() async {
      // TODO(sync): replace with server-reserved receipt ranges (doc §5).
      final maxNo = await db
          .customSelect('SELECT COALESCE(MAX(receipt_no), 0) AS m FROM sales')
          .getSingle();
      final receiptNo = (maxNo.data['m'] as int) + 1;

      await db.into(db.sales).insert(SalesCompanion.insert(
            id: saleId,
            customerId: Value(customerId),
            receiptNo: receiptNo,
            subtotal: Value(subtotal),
            discount: Value(discount),
            vatAmount: Value(vatAmount),
            total: Value(total),
            amountPaid: Value(amountPaid),
            paymentMethod: Value(paymentMethod),
            transferChannel: Value(transferChannel),
            saleDate: now,
          ));

      for (final line in lines) {
        await db.into(db.saleItems).insert(SaleItemsCompanion.insert(
              id: _uuid.v4(),
              saleId: saleId,
              productId: line.productId,
              unitId: Value(line.unitId),
              qty: line.qty,
              qtyBase: line.qtyBase,
              unitPrice: line.unitPrice,
              unitCostSnapshot: Value(line.costPerBase),
            ));

        await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
              id: _uuid.v4(),
              productId: line.productId,
              type: 'sale',
              qty: -line.qtyBase,
              refSaleId: Value(saleId),
              createdAt: now,
            ));

        await (db.update(db.products)
              ..where((p) => p.id.equals(line.productId)))
            .write(ProductsCompanion.custom(
          quantity: db.products.quantity - Variable(line.qtyBase),
        ));
      }

      if (amountPaid > 0) {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: _uuid.v4(),
              saleId: Value(saleId),
              amount: amountPaid,
              method: Value(paymentMethod == 'credit' ? 'cash' : paymentMethod),
              channel: Value(transferChannel),
              createdAt: now,
            ));
      }

      await db.into(db.outbox).insert(OutboxCompanion.insert(
            targetTable: 'sales',
            rowId: saleId,
            op: 'insert',
            payload: '', // Phase 1 sync engine serializes the full row graph
            createdAt: now,
          ));

      return CheckoutResult(saleId: saleId, receiptNo: receiptNo);
    });
  }
}
