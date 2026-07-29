import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/db/database.dart';
import '../../core/db/invoices_repository.dart';
import '../../core/db/settings_repository.dart';
import '../../core/invoice_document.dart';
import '../../core/money.dart';
import '../../core/prompt_dialogs.dart';
import '../../core/providers.dart';
import '../../core/whatsapp.dart';
import 'invoice_form_screen.dart';

/// One invoice: what was billed, what is owed, and every way to chase it.
class InvoiceDetailScreen extends ConsumerWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  static Future<void> open(BuildContext context, String id) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoice = ref.watch(invoiceProvider(invoiceId));
    final shop = ref.watch(shopProfileProvider).valueOrNull ?? const ShopProfile();
    final scheme = Theme.of(context).colorScheme;

    return invoice.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(),
          body: Center(child: Text('Could not load the invoice: $e'))),
      data: (inv) {
        if (inv == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('This invoice no longer exists.')),
          );
        }

        final items = InvoiceItem.decodeAll(inv.items);
        final state = invoiceStateOf(
          status: inv.status,
          total: inv.total,
          amountPaid: inv.amountPaid,
          dueDate: inv.dueDate,
        );
        final owing = inv.total - inv.amountPaid;
        final blocker = conversionBlocker(
          itemsJson: inv.items,
          total: inv.total,
          amountPaid: inv.amountPaid,
          customerId: inv.customerId,
          saleId: inv.saleId,
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(InvoiceDocument.reference(inv.invoiceNo, inv.issuedAt)),
            actions: [
              if (state == InvoiceState.draft)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit',
                  onPressed: () =>
                      InvoiceFormScreen.open(context, existing: inv),
                ),
              PopupMenuButton<String>(
                onSelected: (value) => switch (value) {
                  'cancel' => _confirmCancel(context, ref, inv),
                  'delete' => _confirmDelete(context, ref, inv),
                  _ => null,
                },
                itemBuilder: (_) => [
                  if (state == InvoiceState.draft)
                    const PopupMenuItem(
                        value: 'delete', child: Text('Delete draft')),
                  if (state != InvoiceState.paid &&
                      state != InvoiceState.cancelled)
                    const PopupMenuItem(
                        value: 'cancel', child: Text('Cancel invoice')),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(invoiceStateLabel(state),
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(DateFormat('d MMMM yyyy').format(inv.issuedAt),
                      style: TextStyle(color: scheme.outline)),
                ],
              ),
              if (inv.dueDate != null)
                Text(
                    state == InvoiceState.overdue
                        ? 'Was due ${DateFormat('d MMMM').format(inv.dueDate!)}'
                        : 'Due ${DateFormat('d MMMM').format(inv.dueDate!)}',
                    style: TextStyle(
                        color: state == InvoiceState.overdue
                            ? scheme.error
                            : scheme.outline)),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('BILL TO',
                          style: TextStyle(
                              fontSize: 11,
                              color: scheme.outline,
                              fontWeight: FontWeight.bold)),
                      Text(inv.customerName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (inv.customerPhone != null) Text(inv.customerPhone!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    for (final item in items)
                      ListTile(
                        dense: true,
                        title: Text(item.description),
                        subtitle: Text(
                            '${_qty(item.qty)} × ${formatKoboCompact(item.unitPrice)}'),
                        trailing: Text(formatKoboCompact(item.lineTotal),
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          if (inv.vatAmount > 0) ...[
                            _Row(label: 'Subtotal', value: inv.subtotal),
                            _Row(label: 'VAT', value: inv.vatAmount),
                          ],
                          _Row(label: 'Total', value: inv.total, bold: true),
                          if (inv.amountPaid > 0)
                            _Row(label: 'Paid', value: inv.amountPaid),
                          if (owing > 0)
                            _Row(
                                label: 'Amount due',
                                value: owing,
                                bold: true,
                                color: scheme.error),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (inv.note != null) ...[
                const SizedBox(height: 12),
                Text(inv.note!, style: TextStyle(color: scheme.outline)),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _shareText(context, ref, inv, shop, items),
                      icon: const Icon(Icons.chat_outlined, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _sharePdf(context, ref, inv, shop, items),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (owing > 0)
                FilledButton.icon(
                  onPressed: () => _recordPayment(context, ref, inv),
                  icon: const Icon(Icons.payments_outlined),
                  label: Text('Record payment · ${formatKoboCompact(owing)} due'),
                ),
              if (inv.saleId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('Recorded as a sale — stock and profit updated.',
                      style: TextStyle(color: scheme.primary, fontSize: 12)),
                )
              else ...[
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: blocker != null
                      ? null
                      : () => _convert(context, ref, inv),
                  icon: const Icon(Icons.point_of_sale_outlined),
                  label: const Text('Record as a sale'),
                ),
                if (blocker != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(blocker,
                        style: TextStyle(color: scheme.outline, fontSize: 12)),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();

  String _buildText(Invoice inv, ShopProfile shop, List<InvoiceItem> items) =>
      InvoiceDocument.text(
        shop: shop,
        invoiceNo: inv.invoiceNo,
        issuedAt: inv.issuedAt,
        customerName: inv.customerName,
        items: items,
        subtotal: inv.subtotal,
        vatAmount: inv.vatAmount,
        total: inv.total,
        amountPaid: inv.amountPaid,
        dueDate: inv.dueDate,
        note: inv.note,
      );

  Future<void> _shareText(BuildContext context, WidgetRef ref, Invoice inv,
      ShopProfile shop, List<InvoiceItem> items) async {
    final text = _buildText(inv, shop, items);
    await ref.read(invoicesRepoProvider).markSent(inv.id);

    final sent = await WhatsApp.send(phone: inv.customerPhone, message: text);
    if (!sent) await Share.share(text);
  }

  Future<void> _sharePdf(BuildContext context, WidgetRef ref, Invoice inv,
      ShopProfile shop, List<InvoiceItem> items) async {
    final bytes = await InvoiceDocument.pdf(
      shop: shop,
      invoiceNo: inv.invoiceNo,
      issuedAt: inv.issuedAt,
      customerName: inv.customerName,
      customerPhone: inv.customerPhone,
      items: items,
      subtotal: inv.subtotal,
      vatAmount: inv.vatAmount,
      total: inv.total,
      amountPaid: inv.amountPaid,
      dueDate: inv.dueDate,
      note: inv.note,
    );

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/${InvoiceDocument.fileName(inv.invoiceNo, inv.issuedAt)}');
    await file.writeAsBytes(bytes);

    await ref.read(invoicesRepoProvider).markSent(inv.id);
    await Share.shareXFiles([XFile(file.path)],
        text: 'Invoice ${InvoiceDocument.reference(inv.invoiceNo, inv.issuedAt)}');
  }

  Future<void> _recordPayment(
      BuildContext context, WidgetRef ref, Invoice inv) async {
    final owing = inv.total - inv.amountPaid;
    final amount = await askAmount(
      context,
      title: 'Record payment',
      label: 'Amount received',
      helperText: '${formatKoboCompact(owing)} outstanding',
      initialKobo: owing,
    );

    if (amount != null && amount > 0) {
      await ref
          .read(invoicesRepoProvider)
          .recordPayment(id: inv.id, amount: amount);
    }
  }

  Future<void> _convert(
      BuildContext context, WidgetRef ref, Invoice inv) async {
    final saleId = await ref
        .read(invoicesRepoProvider)
        .convertToSale(inv.id, ref.read(salesRepoProvider));

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(saleId == null
          ? 'Could not record this as a sale.'
          : 'Recorded as a sale — stock and profit updated.'),
    ));
  }

  Future<void> _confirmCancel(
      BuildContext context, WidgetRef ref, Invoice inv) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this invoice?'),
        content: const Text(
            'It stays on record as cancelled so the numbering never has a gap.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cancel invoice')),
        ],
      ),
    );
    if (yes == true) await ref.read(invoicesRepoProvider).cancel(inv.id);
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, Invoice inv) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this draft?'),
        content: const Text('It has not been sent, so nothing is lost.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep it')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (yes == true) {
      await ref.read(invoicesRepoProvider).deleteDraft(inv.id);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  final String label;
  final int value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatKoboCompact(value), style: style),
        ],
      ),
    );
  }
}
