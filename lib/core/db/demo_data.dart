import 'dart:math';

import 'package:drift/drift.dart';

import 'customers_repository.dart';
import 'database.dart';
import 'products_repository.dart';
import 'sales_repository.dart';
import 'settings_repository.dart';

/// A stocked sample shop so a new user sees a working app in the first minute
/// instead of five empty screens (design doc 4.14). Everything lives in local
/// SQLite only and is wiped when they start their real shop.
class DemoData {
  DemoData(this.db);

  final AppDatabase db;

  // Opening stock has to cover two weeks of seeded sales, or the sample shop
  // opens on a wall of "sold beyond stock" warnings that make the app look
  // broken. Semovita is left deliberately thin so the Low chip has something
  // to show.
  static const _products = [
    // name, cost kobo, price kobo, stock
    ('Peak Milk sachet', 30000, 40000, 200.0),
    ('Indomie Chicken', 45000, 55000, 150.0),
    ('Golden Penny Semovita 1kg', 180000, 220000, 40.0),
    ('Bournvita 500g', 450000, 530000, 60.0),
    ('Sugar 1kg', 150000, 190000, 90.0),
    ('Rice 5kg', 900000, 1050000, 60.0),
    ('Ariel Detergent', 80000, 100000, 100.0),
    ('Groundnut Oil 1L', 280000, 340000, 50.0),
  ];

  static const _customers = [
    ('Chidinma Okeke', '08031234567'),
    ('Musa Ibrahim', '08127654321'),
    ('Blessing Adeyemi', '07039876543'),
  ];

  Future<bool> hasData() async {
    final rows = await db.select(db.products).get();
    return rows.isNotEmpty;
  }

  Future<void> load() async {
    final products = ProductsRepository(db);
    final customers = CustomersRepository(db);
    final sales = SalesRepository(db);
    final settings = SettingsRepository(db);

    // The repositories enqueue everything they write, which is right for real
    // records and wrong for these. Sample data is a showroom, not a shop: it
    // must never climb into someone's real books. Noting where the queue
    // stands lets us drop exactly what the seeding adds and nothing else.
    final queueMark = await _outboxHighWater();

    await settings.saveProfile(
      name: 'Sample Provisions',
      phone: '08000000000',
      receiptFooter: 'Thank you! No refund after 7 days.',
      accounts: {'moniepoint': '1234567890', 'opay': '', 'palmpay': '', 'bank': ''},
    );

    final productIds = <String>[];
    for (final (name, cost, price, stock) in _products) {
      productIds.add(await products.create(
        name: name,
        costPrice: cost,
        sellingPrice: price,
        openingStock: stock,
        lowStockLevel: 10,
      ));
    }

    final customerIds = <String>[];
    for (final (name, phone) in _customers) {
      customerIds.add(await customers.create(name: name, phone: phone));
    }

    final stocked = await db.select(db.products).get();
    final byId = {for (final p in stocked) p.id: p};
    final random = Random(7); // fixed seed: the sample shop looks the same twice
    final today = DateTime.now();

    // Two weeks of trading, a few sales a day, some left on credit.
    for (var daysAgo = 13; daysAgo >= 0; daysAgo--) {
      final date = DateTime(today.year, today.month, today.day - daysAgo, 10);
      final salesToday = 2 + random.nextInt(3);

      for (var s = 0; s < salesToday; s++) {
        final lineCount = 1 + random.nextInt(3);
        final chosen = <String>{};
        while (chosen.length < lineCount) {
          chosen.add(productIds[random.nextInt(productIds.length)]);
        }

        final lines = [
          for (final id in chosen)
            CartLine(
              productId: id,
              qty: (1 + random.nextInt(3)).toDouble(),
              unitPrice: byId[id]!.sellingPrice,
              costPerBase: byId[id]!.costPrice,
            ),
        ];

        final total =
            lines.fold<int>(0, (sum, l) => sum + l.lineTotal);
        final roll = random.nextInt(10);

        if (roll < 6) {
          await sales.recordSale(
              lines: lines,
              paymentMethod: 'cash',
              at: date.add(Duration(minutes: s * 47)));
        } else if (roll < 8) {
          await sales.recordSale(
            lines: lines,
            paymentMethod: 'transfer',
            transferChannel: ['opay', 'palmpay', 'moniepoint'][random.nextInt(3)],
            at: date.add(Duration(minutes: s * 47)),
          );
        } else if (roll == 8) {
          // Part payment — the rest becomes tracked debt.
          await sales.recordSale(
            lines: lines,
            paymentMethod: 'cash',
            customerId: customerIds[random.nextInt(customerIds.length)],
            amountPaidOverride: (total * 0.4).round(),
            at: date.add(Duration(minutes: s * 47)),
          );
        } else {
          await sales.recordSale(
            lines: lines,
            paymentMethod: 'credit',
            customerId: customerIds[random.nextInt(customerIds.length)],
            at: date.add(Duration(minutes: s * 47)),
          );
        }
      }
    }

    // Drop only what the seeding queued. Anything already waiting before this
    // ran belongs to a real shop and still needs to go up.
    await (db.delete(db.outbox)..where((o) => o.seq.isBiggerThanValue(queueMark)))
        .go();
  }

  Future<int> _outboxHighWater() async {
    final row = await db
        .customSelect('SELECT COALESCE(MAX(seq), 0) AS m FROM outbox')
        .getSingle();
    return row.data['m'] as int;
  }

  /// Wipes everything. Used before a real shop starts trading.
  Future<void> clear() async {
    await db.transaction(() async {
      await db.delete(db.payments).go();
      await db.delete(db.saleItems).go();
      await db.delete(db.sales).go();
      await db.delete(db.stockMovements).go();
      await db.delete(db.productUnits).go();
      await db.delete(db.products).go();
      await db.delete(db.customers).go();
      await db.delete(db.appSettings).go();
      await db.delete(db.outbox).go();
    });
  }
}
