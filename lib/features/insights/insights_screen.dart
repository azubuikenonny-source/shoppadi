import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/providers.dart';

/// Revenue, profit, and what is still owed (design doc 4.8). Profit is exact:
/// it comes from the cost snapshot written onto every sale line.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _period = 0; // 0 today · 1 week · 2 month

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);
    // A cashier sees what the shop took, never what it made. Markup is the
    // owner's business (design doc section 6).
    final seesProfit = ref.watch(canSeeProfitProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: dashboard.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load figures: $e')),
        data: (data) {
          final summary = switch (_period) {
            0 => data.today,
            1 => data.week,
            _ => data.month,
          };
          final margin = summary.revenue == 0
              ? 0
              : (summary.grossProfit / summary.revenue * 100).round();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Today')),
                  ButtonSegment(value: 1, label: Text('This week')),
                  ButtonSegment(value: 2, label: Text('This month')),
                ],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
              const SizedBox(height: 16),
              _BigStat(
                label: 'Sales',
                value: formatKoboCompact(summary.revenue),
                sub: '${summary.saleCount} sale${summary.saleCount == 1 ? '' : 's'}',
              ),
              if (seesProfit) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Gross profit',
                        value: formatKoboCompact(summary.grossProfit),
                        sub: summary.revenue == 0 ? null : '$margin% margin',
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Stat(
                        label: 'Cost of goods',
                        value: formatKoboCompact(summary.cogs),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Cash collected',
                      value: formatKoboCompact(summary.collected),
                      sub: 'Money in hand',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Stat(
                      label: 'Sold on credit',
                      value: formatKoboCompact(summary.onCredit),
                      sub: summary.onCredit > 0 ? 'Not yet paid' : null,
                      color: summary.onCredit > 0 ? scheme.tertiary : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: Icon(Icons.account_balance_wallet_outlined,
                      color: data.totalOwed > 0 ? scheme.error : scheme.outline),
                  title: const Text('Owed to you, all time'),
                  subtitle: const Text('Across every unpaid sale'),
                  trailing: Text(
                    formatKoboCompact(data.totalOwed),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BigStat extends StatelessWidget {
  const _BigStat({required this.label, required this.value, this.sub});

  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: scheme.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700)),
            if (sub != null)
              Text(sub!,
                  style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub, this.color});

  final String label;
  final String value;
  final String? sub;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: scheme.outline, fontSize: 13)),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: color)),
            if (sub != null)
              Text(sub!,
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
