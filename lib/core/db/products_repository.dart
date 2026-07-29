import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'outbox.dart';

const _uuid = Uuid();

class ProductsRepository {
  ProductsRepository(this.db);

  final AppDatabase db;

  Stream<List<Product>> watchActive() => (db.select(db.products)
        ..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm(expression: p.name)]))
      .watch();

  /// Creates a product and, when [openingStock] > 0, the purchase movement
  /// that puts it on the shelf — so quantity always traces back to the ledger.
  Future<String> create({
    required String name,
    required int costPrice,
    required int sellingPrice,
    String? sku,
    String? barcode,
    String? category,
    String baseUnit = 'piece',
    double openingStock = 0,
    double lowStockLevel = 0,
    bool vatExempt = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await db.into(db.products).insert(ProductsCompanion.insert(
          id: id,
          name: name,
          sku: Value(sku),
          barcode: Value(barcode),
          category: Value(category),
          baseUnit: Value(baseUnit),
          costPrice: Value(costPrice),
          sellingPrice: Value(sellingPrice),
          lowStockLevel: Value(lowStockLevel),
          vatExempt: Value(vatExempt),
          updatedAt: now,
        ));

    if (openingStock > 0) {
      await receiveStock(
        productId: id,
        qty: openingStock,
        unitCost: costPrice,
        note: 'Opening stock',
      );
    }
    await enqueue(db, 'products', id);
    return id;
  }

  Future<void> update({
    required String id,
    required String name,
    required int costPrice,
    required int sellingPrice,
    String? sku,
    String? barcode,
    String? category,
    double lowStockLevel = 0,
    bool vatExempt = false,
  }) async {
    await enqueue(db, 'products', id);
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        name: Value(name),
        sku: Value(sku),
        barcode: Value(barcode),
        category: Value(category),
        costPrice: Value(costPrice),
        sellingPrice: Value(sellingPrice),
        lowStockLevel: Value(lowStockLevel),
        vatExempt: Value(vatExempt),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Stock in (purchase). [qty] is in base units.
  Future<void> receiveStock({
    required String productId,
    required double qty,
    int? unitCost,
    String? note,
  }) async {
    await db.transaction(() async {
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            id: _uuid.v4(),
            productId: productId,
            type: 'purchase',
            qty: qty,
            unitCost: Value(unitCost),
            note: Value(note),
            createdAt: DateTime.now(),
          ));
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion.custom(
        quantity: db.products.quantity + Variable(qty),
      ));
      await enqueue(db, 'products', productId);
    });
  }

  /// Correction after a count, damage, or theft. [delta] may be negative.
  Future<void> adjustStock({
    required String productId,
    required double delta,
    required String reason,
  }) async {
    await db.transaction(() async {
      await db.into(db.stockMovements).insert(StockMovementsCompanion.insert(
            id: _uuid.v4(),
            productId: productId,
            type: 'adjustment',
            qty: delta,
            note: Value(reason),
            createdAt: DateTime.now(),
          ));
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion.custom(
        quantity: db.products.quantity + Variable(delta),
      ));
      await enqueue(db, 'products', productId);
    });
  }

  Future<void> archive(String id) =>
      (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
