import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'outbox.dart';

const _uuid = Uuid();

/// A customer with what they currently owe (design doc 4.5): balance is derived
/// from unpaid sales, never stored — it cannot drift out of sync with the sales.
class Debtor {
  Debtor({required this.customer, required this.balance, this.oldestDebt});

  final Customer customer;
  final int balance; // kobo
  final DateTime? oldestDebt;
}

class CustomersRepository {
  CustomersRepository(this.db);

  final AppDatabase db;

  Stream<List<Customer>> watchAll() => (db.select(db.customers)
        ..orderBy([(c) => OrderingTerm(expression: c.name)]))
      .watch();

  Future<String> create({
    required String name,
    String? phone,
    String? whatsappPhone,
    String? note,
  }) async {
    final id = _uuid.v4();
    await db.into(db.customers).insert(CustomersCompanion.insert(
          id: id,
          name: name,
          phone: Value(phone),
          whatsappPhone: Value(whatsappPhone ?? phone),
          note: Value(note),
          updatedAt: DateTime.now(),
        ));
    await enqueue(db, 'customers', id);
    return id;
  }

  /// Everyone who owes money, biggest debt first.
  Stream<List<Debtor>> watchDebtors() {
    final owed = db.sales.total - db.sales.amountPaid;
    // These expression objects must be reused, not rebuilt: TypedResult.read
    // looks results up by identity, so a second owed.sum() would read null.
    final balance = owed.sum();
    final oldest = db.sales.saleDate.min();

    final query = db.select(db.customers).join([
      innerJoin(db.sales, db.sales.customerId.equalsExp(db.customers.id)),
    ])
      ..where(db.sales.status.equals('completed') & owed.isBiggerThanValue(0))
      ..addColumns([balance, oldest])
      ..groupBy([db.customers.id]);

    return query.watch().map((rows) {
      final debtors = rows.map((row) {
        return Debtor(
          customer: row.readTable(db.customers),
          balance: row.read(balance) ?? 0,
          oldestDebt: row.read(oldest),
        );
      }).toList()
        ..sort((a, b) => b.balance.compareTo(a.balance));
      return debtors;
    });
  }

  /// Applies a repayment to a customer's debts, oldest first.
  Future<void> recordRepayment({
    required String customerId,
    required int amount,
    String method = 'cash',
    String? channel,
  }) async {
    var remaining = amount;
    await db.transaction(() async {
      final unpaid = await (db.select(db.sales)
            ..where((s) =>
                s.customerId.equals(customerId) &
                s.status.equals('completed') &
                s.total.isBiggerThan(s.amountPaid))
            ..orderBy([(s) => OrderingTerm(expression: s.saleDate)]))
          .get();

      for (final sale in unpaid) {
        if (remaining <= 0) break;
        final owing = sale.total - sale.amountPaid;
        final applied = remaining < owing ? remaining : owing;

        await (db.update(db.sales)..where((s) => s.id.equals(sale.id)))
            .write(SalesCompanion(amountPaid: Value(sale.amountPaid + applied)));

        await db.into(db.payments).insert(PaymentsCompanion.insert(
              id: _uuid.v4(),
              saleId: Value(sale.id),
              amount: applied,
              method: Value(method),
              channel: Value(channel),
              createdAt: DateTime.now(),
            ));
        // The sale's amount_paid moved, so the server copy is now stale.
        await enqueue(db, 'sales', sale.id);
        remaining -= applied;
      }
    });
  }
}
