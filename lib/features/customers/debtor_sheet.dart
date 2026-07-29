import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/customers_repository.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import '../../core/whatsapp.dart';

/// Record a repayment or nudge the customer on WhatsApp (design doc 4.5).
class DebtorSheet extends ConsumerStatefulWidget {
  const DebtorSheet({super.key, required this.debtor});

  final Debtor debtor;

  static Future<void> show(BuildContext context, Debtor debtor) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DebtorSheet(debtor: debtor),
    );
  }

  @override
  ConsumerState<DebtorSheet> createState() => _DebtorSheetState();
}

class _DebtorSheetState extends ConsumerState<DebtorSheet> {
  final _amount = TextEditingController();
  String _method = 'cash';
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _recordPayment() async {
    final amount = parseNairaToKobo(_amount.text);
    if (amount == null || amount <= 0) return;
    setState(() => _saving = true);

    await ref.read(customersRepoProvider).recordRepayment(
          customerId: widget.debtor.customer.id,
          amount: amount,
          method: _method,
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${formatKoboCompact(amount)} received from '
          '${widget.debtor.customer.name}'),
    ));
  }

  Future<void> _remind() async {
    final customer = widget.debtor.customer;
    final shop = ref.read(shopProfileProvider).valueOrNull;
    final ok = await WhatsApp.send(
      phone: customer.whatsappPhone ?? customer.phone,
      message: WhatsApp.debtReminder(
        customerName: customer.name,
        amount: formatKoboCompact(widget.debtor.balance),
        businessName: shop?.displayName ?? 'our shop',
      ),
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Add a phone number for this customer first'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    final debtor = widget.debtor;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, insets + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(debtor.customer.name,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              Text(formatKoboCompact(debtor.balance),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: scheme.primary)),
            ],
          ),
          if (debtor.customer.phone != null) ...[
            const SizedBox(height: 2),
            Text(debtor.customer.phone!,
                style: TextStyle(color: scheme.outline)),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount received',
              prefixText: '₦',
              helperText: 'Applied to the oldest debt first',
              suffixIcon: TextButton(
                onPressed: () => setState(() => _amount.text =
                    (debtor.balance / 100).toStringAsFixed(2)),
                child: const Text('All'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final m in const {
                'cash': 'Cash',
                'transfer': 'Transfer',
                'pos': 'POS',
              }.entries)
                ChoiceChip(
                  label: Text(m.value),
                  selected: _method == m.key,
                  onSelected: (_) => setState(() => _method = m.key),
                ),
            ],
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _recordPayment,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Record payment'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _remind,
            icon: const Icon(Icons.chat_outlined),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14)),
            label: const Text('Remind on WhatsApp'),
          ),
        ],
      ),
    );
  }
}
