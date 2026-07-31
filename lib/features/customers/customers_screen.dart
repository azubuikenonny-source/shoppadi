import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/customers_repository.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import 'debtor_sheet.dart';

/// Debtors first — "who owes me money" is the question this screen answers
/// (design doc 4.5). Everyone else sits under the second tab.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtors = ref.watch(debtorsProvider);
    final customers = ref.watch(customersProvider);
    final scheme = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Customers'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Owing'),
            Tab(text: 'Everyone'),
          ]),
        ),
        body: TabBarView(
          children: [
            debtors.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load debts: $e')),
              data: (list) {
                final total =
                    list.fold<int>(0, (sum, d) => sum + d.balance);
                return Column(
                  children: [
                    Card(
                      margin: const EdgeInsets.all(16),
                      child: ListTile(
                        leading: Icon(Icons.account_balance_wallet_outlined,
                            color: scheme.primary),
                        title: const Text('Total owed to you'),
                        subtitle: Text(list.isEmpty
                            ? 'Nobody is owing'
                            : '${list.length} customer${list.length == 1 ? '' : 's'}'),
                        trailing: Text(
                          formatKoboCompact(total),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(color: scheme.primary),
                        ),
                      ),
                    ),
                    Expanded(
                      child: list.isEmpty
                          ? Center(
                              child: Text('No outstanding debts',
                                  style: TextStyle(color: scheme.outline)),
                            )
                          : RefreshIndicator(
                              onRefresh: () async => await ref
                                  .read(syncEngineProvider)
                                  .syncNow(),
                              child: ListView.separated(
                                itemCount: list.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (_, i) =>
                                    _DebtorTile(debtor: list[i]),
                              ),
                            ),
                    ),
                  ],
                );
              },
            ),
            customers.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load: $e')),
              data: (list) => list.isEmpty
                  ? Center(
                      child: Text('No customers yet',
                          style: TextStyle(color: scheme.outline)))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => ListTile(
                        title: Text(list[i].name),
                        subtitle:
                            list[i].phone == null ? null : Text(list[i].phone!),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DebtorTile extends StatelessWidget {
  const _DebtorTile({required this.debtor});

  final Debtor debtor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final age = debtor.oldestDebt == null
        ? null
        : DateTime.now().difference(debtor.oldestDebt!).inDays;
    final stale = age != null && age >= 30;

    return ListTile(
      title: Text(debtor.customer.name),
      subtitle: age == null
          ? null
          : Text(
              age == 0 ? 'Since today' : 'Oldest debt $age day${age == 1 ? '' : 's'} ago',
              style: TextStyle(color: stale ? scheme.error : scheme.outline),
            ),
      trailing: Text(
        formatKoboCompact(debtor.balance),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onTap: () => DebtorSheet.show(context, debtor),
    );
  }
}
