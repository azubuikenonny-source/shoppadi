import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'dart:async';

import '../../core/channels.dart';
import '../../core/printing/thermal_receipt.dart';
import '../../core/db/sales_repository.dart';
import '../../core/money.dart';
import '../../core/prompt_dialogs.dart';
import '../../core/providers.dart';
import '../../core/receipt.dart';
import '../../core/whatsapp.dart';
import 'cart.dart';

/// Checkout (design doc 4.1). Credit and part-payment require a customer —
/// that is what turns a sale into a tracked debt.
class CheckoutSheet extends ConsumerStatefulWidget {
  const CheckoutSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const CheckoutSheet(),
    );
  }

  @override
  ConsumerState<CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<CheckoutSheet> {
  String _method = 'cash';
  String _channel = 'opay';
  String? _customerId;
  final _paidController = TextEditingController();
  final _discountController = TextEditingController();
  bool _saving = false;

  bool get _needsCustomer => _method == 'credit' || _partialAmount != null;

  /// Money knocked off at the counter (design doc 4.1). Clamped to the
  /// subtotal: a shop can give something away, but a sale can never owe the
  /// customer money.
  int get _discount {
    final typed = parseNairaToKobo(_discountController.text) ?? 0;
    final subtotal = ref.read(cartTotalProvider);
    return typed.clamp(0, subtotal);
  }

  /// What the customer actually owes after the discount — every payment
  /// comparison below runs against this, not the shelf-price subtotal.
  int get _dueTotal => ref.read(cartTotalProvider) - _discount;

  /// Set only when the cashier typed an amount lower than what is due.
  int? get _partialAmount {
    final typed = parseNairaToKobo(_paidController.text);
    if (typed == null) return null;
    return typed < _dueTotal ? typed : null;
  }

  @override
  void dispose() {
    _paidController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    // Everything is captured before the cart is cleared — the getters below
    // read cart state, which is empty by the time the receipt is built.
    final discount = _discount;
    final total = _dueTotal;
    final entries = ref.read(cartProvider);
    final paid = _method == 'credit' ? 0 : (_partialAmount ?? total);
    final balance = total - paid;

    String? customerName;
    String? customerPhone;
    if (_customerId != null) {
      for (final c in ref.read(customersProvider).valueOrNull ?? const []) {
        if (c.id == _customerId) {
          customerName = c.name;
          customerPhone = c.whatsappPhone ?? c.phone;
          break;
        }
      }
    }

    setState(() => _saving = true);

    final lines = entries
        .map((e) => CartLine(
              productId: e.product.id,
              qty: e.qty,
              unitPrice: e.product.sellingPrice,
              costPerBase: e.product.costPrice,
              vatExempt: e.product.vatExempt,
            ))
        .toList();

    try {
      final shop = await ref.read(settingsRepoProvider).load();
      final result = await ref.read(salesRepoProvider).recordSale(
            lines: lines,
            paymentMethod: _method,
            transferChannel: _method == 'transfer' ? _channel : null,
            customerId: _customerId,
            discount: discount,
            amountPaidOverride: _method == 'credit' ? 0 : _partialAmount,
          );

      final receipt = Receipt.build(
        shop: shop,
        receiptNo: result.receiptNo,
        lines: [
          for (final e in entries)
            ReceiptLine(
                name: e.product.name, qty: e.qty, lineTotal: e.lineTotal),
        ],
        total: total,
        amountPaid: paid,
        discount: discount,
        customerName: customerName,
      );

      // Print before clearing: at a busy counter the paper should already be
      // coming out while the next customer steps up.
      if (shop.autoPrint && shop.hasPrinter) {
        unawaited(ref.read(printerServiceProvider).send(
              ThermalReceipt.bytes(
                shop: shop,
                receiptNo: result.receiptNo,
                items: [
                  for (final e in entries)
                    ReceiptLine(
                        name: e.product.name,
                        qty: e.qty,
                        lineTotal: e.lineTotal),
                ],
                total: total,
                amountPaid: paid,
                discount: discount,
                customerName: customerName,
                width: shop.paperWidth,
              ),
              mac: shop.printerMac,
            ));
      }

      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(balance > 0
            ? 'Receipt #${result.receiptNo} · ${formatKoboCompact(balance)} owing'
            : 'Receipt #${result.receiptNo} · ${formatKoboCompact(paid)} paid'),
        action: SnackBarAction(
          label: 'Send receipt',
          onPressed: () => _sendReceipt(receipt, customerPhone),
        ),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      setState(() => _saving = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not save sale: $e')));
    }
  }

  /// Straight to the customer's WhatsApp when we know their number, otherwise
  /// the system share sheet so a walk-in can still be sent their receipt.
  Future<void> _sendReceipt(String receipt, String? phone) async {
    if (phone != null && await WhatsApp.send(phone: phone, message: receipt)) {
      return;
    }
    await Share.share(receipt);
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(cartProvider);
    final subtotal = ref.watch(cartTotalProvider);
    final discount = _discount;
    final total = subtotal - discount;
    final customers = ref.watch(customersProvider);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;
    final blocked = _needsCustomer && _customerId == null;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, insets + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Checkout',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(formatKoboCompact(total),
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: scheme.primary)),
              ],
            ),
            const SizedBox(height: 12),
            ...entries.map((e) => _CartRow(entry: e)),
            if (discount > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Discount', style: TextStyle(color: scheme.tertiary)),
                    Text('-${formatKoboCompact(discount)}',
                        style: TextStyle(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const Divider(height: 24),
            TextField(
              controller: _discountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Discount',
                prefixText: '₦',
                helperText: 'Optional — knocked off the total',
              ),
            ),
            const SizedBox(height: 12),
            Text('Payment method',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in const {
                  'cash': 'Cash',
                  'transfer': 'Transfer',
                  'pos': 'POS',
                  'credit': 'Credit',
                }.entries)
                  ChoiceChip(
                    label: Text(m.value),
                    selected: _method == m.key,
                    onSelected: (_) => setState(() => _method = m.key),
                  ),
              ],
            ),
            if (_method == 'transfer') ...[
              const SizedBox(height: 12),
              Text('Paid into', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final key in transferChannels)
                    ChoiceChip(
                      label: Text(channelLabel(key)),
                      selected: _channel == key,
                      onSelected: (_) => setState(() => _channel = key),
                    ),
                ],
              ),
            ],
            if (_method != 'credit') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _paidController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Amount paid',
                  prefixText: '₦',
                  hintText: (total / 100).toStringAsFixed(2),
                  helperText: _partialAmount == null
                      ? 'Leave blank if paying in full'
                      : 'Balance of ${formatKoboCompact(total - _partialAmount!)} goes on credit',
                ),
              ),
            ],
            if (_needsCustomer) ...[
              const SizedBox(height: 12),
              customers.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Could not load customers: $e'),
                data: (list) => Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _customerId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Who is owing?'),
                        items: [
                          for (final c in list)
                            DropdownMenuItem(
                                value: c.id, child: Text(c.name)),
                        ],
                        onChanged: (v) => setState(() => _customerId = v),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_add_outlined),
                      tooltip: 'New customer',
                      onPressed: _addCustomer,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: (_saving || blocked) ? null : _complete,
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(blocked ? 'Choose a customer' : 'Complete sale'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCustomer() async {
    final details = await askNewCustomer(context);
    if (details == null) return;

    final id = await ref
        .read(customersRepoProvider)
        .create(name: details.name, phone: details.phone);
    if (mounted) setState(() => _customerId = id);
  }
}

class _CartRow extends ConsumerWidget {
  const _CartRow({required this.entry});

  final CartEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(cartProvider.notifier);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(entry.product.name)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: () =>
                notifier.setQty(entry.product.id, entry.qty - 1),
          ),
          Text(entry.qty.toStringAsFixed(0),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () =>
                notifier.setQty(entry.product.id, entry.qty + 1),
          ),
          SizedBox(
            width: 88,
            child: Text(formatKoboCompact(entry.lineTotal),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}
