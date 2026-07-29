import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/invoices_repository.dart';
import '../../core/invoice_document.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import 'invoice_detail_screen.dart';
import 'invoice_form_screen.dart';

/// Who has been billed and who still owes (design doc 4.3).
class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const InvoicesScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: invoices.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load invoices: $e')),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.receipt_long_outlined,
                      size: 56, color: scheme.outline),
                  const SizedBox(height: 12),
                  Text('No invoices yet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Bill a customer before they collect their goods.',
                      style: TextStyle(color: scheme.outline)),
                ],
              ),
            );
          }

          final unpaid = list.where((i) {
            final state = _stateOf(i);
            return state == InvoiceState.sent ||
                state == InvoiceState.overdue ||
                state == InvoiceState.partlyPaid;
          });
          final owed = unpaid.fold<int>(0, (sum, i) => sum + i.total - i.amountPaid);

          return Column(
            children: [
              if (owed > 0)
                Card(
                  margin: const EdgeInsets.all(16),
                  child: ListTile(
                    leading: Icon(Icons.pending_actions_outlined,
                        color: scheme.primary),
                    title: const Text('Awaiting payment'),
                    subtitle: Text(
                        '${unpaid.length} invoice${unpaid.length == 1 ? '' : 's'}'),
                    trailing: Text(formatKoboCompact(owed),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: scheme.primary)),
                  ),
                ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _InvoiceTile(invoice: list[i]),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => InvoiceFormScreen.open(context),
        icon: const Icon(Icons.add),
        label: const Text('New invoice'),
      ),
    );
  }

  static InvoiceState _stateOf(Invoice invoice) => invoiceStateOf(
        status: invoice.status,
        total: invoice.total,
        amountPaid: invoice.amountPaid,
        dueDate: invoice.dueDate,
      );
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = InvoicesScreen._stateOf(invoice);
    final color = switch (state) {
      InvoiceState.paid => scheme.primary,
      InvoiceState.overdue => scheme.error,
      InvoiceState.partlyPaid => scheme.tertiary,
      InvoiceState.draft => scheme.outline,
      InvoiceState.cancelled => scheme.outline,
      InvoiceState.sent => scheme.secondary,
    };

    return ListTile(
      title: Row(
        children: [
          Expanded(
            child: Text(invoice.customerName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(invoiceStateLabel(state),
                style: TextStyle(
                    fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      subtitle: Text([
        InvoiceDocument.reference(invoice.invoiceNo, invoice.issuedAt),
        DateFormat('d MMM').format(invoice.issuedAt),
        if (invoice.dueDate != null)
          'due ${DateFormat('d MMM').format(invoice.dueDate!)}',
      ].join(' · ')),
      trailing: Text(formatKoboCompact(invoice.total),
          style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () => InvoiceDetailScreen.open(context, invoice.id),
    );
  }
}
