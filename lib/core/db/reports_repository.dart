import 'package:drift/drift.dart';

import 'database.dart';

/// Money figures for one period. Profit is exact, not estimated: it uses the
/// cost snapshot stored on each sale line (design doc 4.8).
class PeriodSummary {
  const PeriodSummary({
    required this.revenue,
    required this.cogs,
    required this.saleCount,
    required this.collected,
  });

  final int revenue; // kobo billed
  final int cogs; // kobo cost of what was sold
  final int saleCount;
  final int collected; // kobo actually received

  int get grossProfit => revenue - cogs;
  int get onCredit => revenue - collected;

  static const empty =
      PeriodSummary(revenue: 0, cogs: 0, saleCount: 0, collected: 0);
}

class DashboardData {
  const DashboardData({
    required this.today,
    required this.week,
    required this.month,
    required this.totalOwed,
  });

  final PeriodSummary today;
  final PeriodSummary week;
  final PeriodSummary month;
  final int totalOwed;
}

class ReportsRepository {
  ReportsRepository(this.db);

  final AppDatabase db;

  Stream<DashboardData> watchDashboard() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final week = today.subtract(Duration(days: now.weekday - 1));
    final month = DateTime(now.year, now.month);

    // Placeholders are positional, so each period's cutoff is passed once per
    // sub-select, in the order the sub-selects appear.
    String block(String prefix) => '''
        (SELECT COALESCE(SUM(total), 0) FROM sales
          WHERE status = 'completed' AND sale_date >= ?) AS ${prefix}_revenue,
        (SELECT COALESCE(SUM(amount_paid), 0) FROM sales
          WHERE status = 'completed' AND sale_date >= ?) AS ${prefix}_paid,
        (SELECT COUNT(*) FROM sales
          WHERE status = 'completed' AND sale_date >= ?) AS ${prefix}_count,
        (SELECT COALESCE(SUM(si.qty_base * si.unit_cost_snapshot), 0)
          FROM sale_items si JOIN sales s ON s.id = si.sale_id
          WHERE s.status = 'completed' AND s.sale_date >= ?) AS ${prefix}_cogs''';

    return db.customSelect(
      '''
      SELECT
${block('today')},
${block('week')},
${block('month')},
        (SELECT COALESCE(SUM(total - amount_paid), 0) FROM sales
          WHERE status = 'completed' AND total > amount_paid) AS total_owed
      ''',
      variables: [
        for (final cutoff in [today, week, month])
          for (var i = 0; i < 4; i++) Variable<DateTime>(cutoff),
      ],
      readsFrom: {db.sales, db.saleItems},
    ).watchSingle().map((row) {
      PeriodSummary read(String prefix) => PeriodSummary(
            revenue: row.read<int>('${prefix}_revenue'),
            cogs: row.read<int>('${prefix}_cogs'),
            saleCount: row.read<int>('${prefix}_count'),
            collected: row.read<int>('${prefix}_paid'),
          );

      return DashboardData(
        today: read('today'),
        week: read('week'),
        month: read('month'),
        totalOwed: row.read<int>('total_owed'),
      );
    });
  }
}
