import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

const _uuid = Uuid();

/// A sold line with its product name, ready to show in a return sheet.
class SaleLine {
  const SaleLine({required this.item, required this.productName});

  final SaleItem item;
  final String productName;
}

/// One entry in a stored return.
class ReturnedItem {
  const ReturnedItem({
    required this.name,
    required this.qty,
    required this.value,
  });

  final String name;
  final double qty;
  final int value; // kobo, before the sale's discount is applied

  static List<ReturnedItem> decodeAll(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    return [
      for (final entry in list.cast<Map<String, dynamic>>())
        ReturnedItem(
          name: entry['name'] as String? ?? 'Item',
          qty: (entry['qty'] as num).toDouble(),
          value: (entry['value'] as num).toInt(),
        ),
    ];
  }
}

/// Splits a total across discount and VAT the same way the original sale did,
/// so a partial return leaves the sale internally consistent.
class ReturnMaths {
  const ReturnMaths({
    required this.subtotal,
    required this.discount,
    required this.vatAmount,
    required this.total,
    required this.refund,
  });

  final int subtotal;
  final int discount;
  final int vatAmount;
  final int total;
  final int refund;

  /// [returnedGross] is the pre-discount value of the goods coming back.
  factory ReturnMaths.from({
    required int oldSubtotal,
    required int oldDiscount,
    required int oldVat,
    required int oldTotal,
    required int returnedGross,
  }) {
    final subtotal = oldSubtotal - returnedGross;
    final scale = oldSubtotal == 0 ? 0.0 : subtotal / oldSubtotal;
    final discount = (oldDiscount * scale).round();
    final vat = (oldVat * scale).round();
    final total = subtotal - discount;
    return ReturnMaths(
      subtotal: subtotal,
      discount: discount,
      vatAmount: vat,
      total: total,
      refund: oldTotal - total,
    );
  }
}

class ReturnsRepository {
  ReturnsRepository(this.db);

  final AppDatabase db;

  Stream<List<SaleLine>> watchLines(String saleId) {
    final query = db.select(db.saleItems).join([
      innerJoin(db.products, db.products.id.equalsExp(db.saleItems.productId)),
    ])
      ..where(db.saleItems.saleId.equals(saleId));

    return query.watch().map((rows) => [
          for (final row in rows)
            SaleLine(
              item: row.readTable(db.saleItems),
              productName: row.readTable(db.products).name,
            ),
        ]);
  }

  Stream<List<Return>> watchReturns(String saleId) =>
      (db.select(db.returns)
            ..where((r) => r.saleId.equals(saleId))
            ..orderBy([
              (r) => OrderingTerm(
                  expression: r.createdAt, mode: OrderingMode.desc)
            ]))
          .watch();

  Stream<Sale?> watchSale(String saleId) =>
      (db.select(db.sales)..where((s) => s.id.equals(saleId)))
          .watchSingleOrNull();

  /// Takes goods back. Shrinks the sold lines (so revenue and COGS drop by
  /// exactly the right amount), returns stock to the shelf unless it is being
  /// written off, and either refunds money or credits the customer's debt.
  ///
  /// Returns the amount refunded or credited, in kobo.
  Future<int> recordReturn({
    required String saleId,
    required Map<String, double> qtyBySaleItem,
    required bool restock,
    required String refundMethod, // cash | transfer | debt_credit
    String? channel,
    String? reason,
  }) async {
    final now = DateTime.now();
    final trimmedReason =
        (reason == null || reason.trim().isEmpty) ? null : reason.trim();

    return db.transaction(() async {
      final sale = await (db.select(db.sales)..where((s) => s.id.equals(saleId)))
          .getSingleOrNull();
      if (sale == null) return 0;

      final lines = await watchLines(saleId).first;
      final byId = {for (final line in lines) line.item.id: line};

      var returnedGross = 0;
      final recorded = <Map<String, dynamic>>[];

      for (final entry in qtyBySaleItem.entries) {
        final line = byId[entry.key];
        if (line == null) continue;
        final item = line.item;
        final qty = entry.value.clamp(0.0, item.qty).toDouble();
        if (qty <= 0) continue;

        // Pack units: convert the returned quantity back to base units.
        final perUnitBase = item.qty == 0 ? 0.0 : item.qtyBase / item.qty;
        final qtyBase = qty * perUnitBase;
        final lineValue = (qty * item.unitPrice).round();
        returnedGross += lineValue;

        recorded.add({
          'saleItemId': item.id,
          'productId': item.productId,
          'name': line.productName,
          'qty': qty,
          'value': lineValue,
        });

        final remainingQty = item.qty - qty;
        if (remainingQty <= 0.0001) {
          await (db.delete(db.saleItems)..where((i) => i.id.equals(item.id)))
              .go();
        } else {
          await (db.update(db.saleItems)..where((i) => i.id.equals(item.id)))
              .write(SaleItemsCompanion(
            qty: Value(remainingQty),
            qtyBase: Value(item.qtyBase - qtyBase),
          ));
        }

        // The goods physically came back either way — record that first.
        await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
              id: _uuid.v4(),
              productId: item.productId,
              type: 'return',
              qty: qtyBase,
              note: Value(trimmedReason),
              refSaleId: Value(saleId),
              createdAt: now,
            ));

        if (restock) {
          await (db.update(db.products)
                ..where((p) => p.id.equals(item.productId)))
              .write(ProductsCompanion.custom(
            quantity: db.products.quantity + Variable(qtyBase),
          ));
        } else {
          // Damaged: back in, then written off, so the ledger tells the whole
          // story instead of the goods quietly never existing.
          await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
                id: _uuid.v4(),
                productId: item.productId,
                type: 'adjustment',
                qty: -qtyBase,
                note: const Value('Written off — damaged return'),
                refSaleId: Value(saleId),
                createdAt: now,
              ));
        }
      }

      if (recorded.isEmpty) return 0;

      final maths = ReturnMaths.from(
        oldSubtotal: sale.subtotal,
        oldDiscount: sale.discount,
        oldVat: sale.vatAmount,
        oldTotal: sale.total,
        returnedGross: returnedGross,
      );

      var newPaid = sale.amountPaid;
      if (refundMethod == 'debt_credit') {
        // Money stays put; the debt shrinks because the total dropped.
        if (newPaid > maths.total) newPaid = maths.total;
      } else {
        final cashBack =
            maths.refund > sale.amountPaid ? sale.amountPaid : maths.refund;
        if (cashBack > 0) {
          await db.into(db.payments).insert(PaymentsCompanion.insert(
                id: _uuid.v4(),
                saleId: Value(saleId),
                amount: -cashBack, // money leaving the till today
                method: Value(refundMethod),
                channel: Value(channel),
                createdAt: now,
              ));
        }
        newPaid = sale.amountPaid - cashBack;
      }

      final leftover = await (db.select(db.saleItems)
            ..where((i) => i.saleId.equals(saleId)))
          .get();

      await (db.update(db.sales)..where((s) => s.id.equals(saleId)))
          .write(SalesCompanion(
        subtotal: Value(maths.subtotal),
        discount: Value(maths.discount),
        vatAmount: Value(maths.vatAmount),
        total: Value(maths.total),
        amountPaid: Value(newPaid),
        // Partly-returned sales stay 'completed' so they keep counting toward
        // revenue at their reduced value; only a full return leaves the books.
        status: Value(leftover.isEmpty ? 'returned' : 'completed'),
      ));

      final returnId = _uuid.v4();
      await db.into(db.returns).insert(ReturnsCompanion.insert(
            id: returnId,
            saleId: saleId,
            items: jsonEncode(recorded),
            restock: Value(restock),
            refundMethod: refundMethod,
            channel: Value(channel),
            amount: maths.refund,
            reason: Value(trimmedReason),
            createdAt: now,
          ));

      await db.into(db.outbox).insert(OutboxCompanion.insert(
            targetTable: 'returns',
            rowId: returnId,
            op: 'insert',
            payload: '',
            createdAt: now,
          ));

      return maths.refund;
    });
  }
}
