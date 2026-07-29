import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/channels.dart';
import '../../core/db/sales_repository.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import 'sale_detail_screen.dart';

/// Past receipts — the list you open when a customer walks back in, either to
/// re-send a receipt or to return something.
class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const SalesScreen()));

  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sales = ref.watch(recentSalesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receipts')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Receipt number or customer…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: sales.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load receipts: $e')),
              data: (all) {
                final list = _query.isEmpty
                    ? all
                    : all.where((s) {
                        final name = s.customerName?.toLowerCase() ?? '';
                        return '${s.sale.receiptNo}'.contains(_query) ||
                            name.contains(_query);
                      }).toList();

                if (list.isEmpty) {
                  return Center(
                    child: Text(
                        all.isEmpty ? 'No sales yet' : 'Nothing matches "$_query"',
                        style: TextStyle(color: scheme.outline)),
                  );
                }

                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _SaleTile(summary: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleTile extends StatelessWidget {
  const _SaleTile({required this.summary});

  final SaleSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sale = summary.sale;
    final method = sale.paymentMethod == 'transfer' && sale.transferChannel != null
        ? channelLabel(sale.transferChannel!)
        : channelLabel(sale.paymentMethod);

    return ListTile(
      title: Row(
        children: [
          Text('Receipt #${sale.receiptNo}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          if (sale.status == 'returned')
            _Tag(label: 'Returned', color: scheme.outline),
          if (sale.status == 'completed' && summary.balance > 0)
            _Tag(
                label: 'Owing ${formatKoboCompact(summary.balance)}',
                color: scheme.error),
        ],
      ),
      subtitle: Text([
        DateFormat('d MMM').format(sale.saleDate),
        method,
        if (summary.customerName != null) summary.customerName!,
      ].join(' · ')),
      trailing: Text(formatKoboCompact(sale.total),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () => SaleDetailScreen.open(context, sale.id),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
