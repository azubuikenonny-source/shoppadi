import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Local source of truth (design doc section 5): the UI reads and writes
/// SQLite only; the Outbox table queues every mutation for background sync.
/// Ids are client-generated UUIDs so offline writes merge without conflict.
/// Money columns are integer kobo; quantities are REAL in base units.

class Products extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get sku => text().nullable()();
  TextColumn get barcode => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get baseUnit => text().withDefault(const Constant('piece'))();
  IntColumn get costPrice => integer().withDefault(const Constant(0))();
  IntColumn get sellingPrice => integer().withDefault(const Constant(0))();
  RealColumn get quantity => real().withDefault(const Constant(0))();
  RealColumn get lowStockLevel => real().withDefault(const Constant(0))();
  BoolColumn get vatExempt => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class ProductUnits extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get unitName => text()();
  RealColumn get factorToBase => real()();
  IntColumn get sellingPrice => integer()();
  TextColumn get barcode => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get whatsappPhone => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get customerId => text().nullable().references(Customers, #id)();
  IntColumn get receiptNo => integer()();
  IntColumn get subtotal => integer().withDefault(const Constant(0))();
  IntColumn get discount => integer().withDefault(const Constant(0))();
  IntColumn get vatAmount => integer().withDefault(const Constant(0))();
  IntColumn get total => integer().withDefault(const Constant(0))();
  IntColumn get amountPaid => integer().withDefault(const Constant(0))();
  TextColumn get paymentMethod => text().withDefault(const Constant('cash'))();
  TextColumn get transferChannel => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get saleDate => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().references(Sales, #id)();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get unitId => text().nullable()();
  RealColumn get qty => real()();
  RealColumn get qtyBase => real()();
  IntColumn get unitPrice => integer()();
  IntColumn get unitCostSnapshot => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {id};
}

class StockMovements extends Table {
  TextColumn get id => text()();
  TextColumn get productId => text().references(Products, #id)();
  TextColumn get type => text()(); // purchase | sale | adjustment | return
  RealColumn get qty => real()(); // signed, base units
  IntColumn get unitCost => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get refSaleId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().nullable()();
  IntColumn get amount => integer()(); // negative = refund out
  TextColumn get method => text().withDefault(const Constant('cash'))();
  TextColumn get channel => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Shop profile and preferences, one row per key. Key/value keeps later
/// additions (VAT toggle, receipt footer, printer id) from needing migrations.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

/// A bill sent to a customer (design doc 4.3). The customer's details are
/// snapshotted: an invoice is a document, so it must not change when a
/// customer record is later edited.
class Invoices extends Table {
  TextColumn get id => text()();
  IntColumn get invoiceNo => integer()();
  TextColumn get customerId => text().nullable()();
  TextColumn get customerName => text()();
  TextColumn get customerPhone => text().nullable()();
  TextColumn get items => text()(); // JSON: [{productId?, description, qty, unitPrice, costPerUnit?}]
  IntColumn get subtotal => integer()();
  IntColumn get vatAmount => integer().withDefault(const Constant(0))();
  IntColumn get total => integer()();
  IntColumn get amountPaid => integer().withDefault(const Constant(0))();
  DateTimeColumn get issuedAt => dateTime()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get note => text().nullable()();
  TextColumn get saleId => text().nullable()(); // set once it becomes a real sale
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Goods coming back (design doc 4.13). The sale itself shrinks so revenue,
/// COGS and debt stay exact; this row is the audit trail of what came back.
class Returns extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text()();
  TextColumn get items => text()(); // JSON: [{saleItemId, productId, name, qty, value}]
  BoolColumn get restock => boolean().withDefault(const Constant(true))();
  TextColumn get refundMethod => text()(); // cash | transfer | debt_credit
  TextColumn get channel => text().nullable()();
  IntColumn get amount => integer()(); // kobo refunded or credited
  TextColumn get reason => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// One row per till close (design doc 4.12). Discrepancies are permanent —
/// they can be explained, never edited away, which is the whole point.
class DayCloses extends Table {
  TextColumn get id => text()();
  DateTimeColumn get closeDate => dateTime()(); // midnight of the day closed
  IntColumn get expectedCash => integer()();
  IntColumn get countedCash => integer()();
  TextColumn get channelTotals => text()(); // JSON: {cash, opay, moniepoint…}
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Sync queue: one row per pending mutation, pushed in order, deleted on ack.
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get targetTable => text()();
  TextColumn get rowId => text()();
  TextColumn get op => text()(); // insert | update
  TextColumn get payload => text()(); // row as JSON
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [
  Products,
  ProductUnits,
  Customers,
  Sales,
  SaleItems,
  StockMovements,
  Payments,
  AppSettings,
  DayCloses,
  Returns,
  Invoices,
  Outbox,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(driftDatabase(name: 'shoppadi'));

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(dayCloses);
          if (from < 3) await m.createTable(returns);
          if (from < 4) await m.createTable(invoices);
        },
      );
}
