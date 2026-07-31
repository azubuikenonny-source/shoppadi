import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/channels.dart';
import '../../core/db/database.dart';
import '../../core/db/returns_repository.dart';
import '../../core/db/settings_repository.dart';
import '../../core/money.dart';
import '../../core/printing/printer_service.dart';
import '../../core/printing/thermal_receipt.dart';
import '../../core/providers.dart';
import '../../core/receipt.dart';
import 'return_sheet.dart';

/// One receipt: what was sold, what was paid, what came back.
class SaleDetailScreen extends ConsumerWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  static Future<void> open(BuildContext context, String saleId) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SaleDetailScreen(saleId: saleId)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sale = ref.watch(saleProvider(saleId));
    final lines = ref.watch(saleLinesProvider(saleId));
    final returns = ref.watch(saleReturnsProvider(saleId));
    // Handing money back is a manager's call (design doc section 6). The
    // server would reject a cashier's return anyway; better the button is
    // honest than the sync queue jams on a refusal.
    final canReturn =
        ref.watch(membershipProvider).valueOrNull?.canRecordMoneyOut ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(switch (sale) {
          AsyncData(value: final s) when s != null => 'Receipt #${s.receiptNo}',
          _ => 'Receipt',
        }),
      ),
      body: switch ((sale, lines)) {
        (AsyncData(value: final s), AsyncData(value: final l)) => s == null
            ? const Center(child: Text('This sale no longer exists.'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(DateFormat('EEEE d MMMM, h:mm a').format(s.saleDate),
                      style: TextStyle(color: scheme.outline)),
                  const SizedBox(height: 16),
                  if (l.isEmpty)
                    Card(
                      color: scheme.surfaceContainerHighest,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                            'Everything on this receipt was returned.'),
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final line in l)
                            ListTile(
                              dense: true,
                              title: Text(line.productName),
                              subtitle: Text(
                                  '${_qty(line.item.qty)} × ${formatKoboCompact(line.item.unitPrice)}'),
                              trailing: Text(
                                  formatKoboCompact(
                                      (line.item.qty * line.item.unitPrice)
                                          .round()),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                  _Totals(sale: s),
                  const SizedBox(height: 16),
                  returns.maybeWhen(
                    data: (list) => list.isEmpty
                        ? const SizedBox.shrink()
                        : _ReturnsCard(returns: list),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _share(context, ref, s, l),
                          icon: const Icon(Icons.share_outlined, size: 18),
                          label: const Text('Share'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _print(context, ref, s, l),
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('Print'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (l.isNotEmpty && canReturn)
                    FilledButton.tonalIcon(
                      onPressed: () =>
                          ReturnSheet.show(context, saleId: saleId, sale: s),
                      icon: const Icon(Icons.assignment_return_outlined),
                      label: const Text('Return items'),
                    )
                  else if (l.isNotEmpty)
                    Text(
                      'Returns need a manager or the owner.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.outline, fontSize: 12),
                    ),
                ],
              ),
        (AsyncError(error: final e), _) || (_, AsyncError(error: final e)) =>
          Center(child: Text('Could not load the receipt: $e')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    Sale sale,
    List<SaleLine> lines,
  ) async {
    final shop = ref.read(shopProfileProvider).valueOrNull;
    if (shop == null) return;

    final text = Receipt.build(
      shop: shop,
      receiptNo: sale.receiptNo,
      lines: [
        for (final line in lines)
          ReceiptLine(
            name: line.productName,
            qty: line.item.qty,
            lineTotal: (line.item.qty * line.item.unitPrice).round(),
          ),
      ],
      total: sale.total,
      amountPaid: sale.amountPaid,
      discount: sale.discount,
      at: sale.saleDate,
    );

    await Share.share(text);
  }

  Future<void> _print(
    BuildContext context,
    WidgetRef ref,
    Sale sale,
    List<SaleLine> lines,
  ) async {
    final shop = ref.read(shopProfileProvider).valueOrNull;
    if (shop == null) return;

    final outcome = await printSale(ref, sale: sale, lines: lines, shop: shop);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(printOutcomeMessage(outcome))));
  }
}

/// Shared by the Print button and by auto-print at checkout, so a receipt
/// always comes out the same regardless of where it was triggered.
Future<PrintOutcome> printSale(
  WidgetRef ref, {
  required Sale sale,
  required List<SaleLine> lines,
  required ShopProfile shop,
  String? customerName,
}) {
  return ref.read(printerServiceProvider).send(
        ThermalReceipt.bytes(
          shop: shop,
          receiptNo: sale.receiptNo,
          items: [
            for (final line in lines)
              ReceiptLine(
                name: line.productName,
                qty: line.item.qty,
                lineTotal: (line.item.qty * line.item.unitPrice).round(),
              ),
          ],
          total: sale.total,
          amountPaid: sale.amountPaid,
          discount: sale.discount,
          vatAmount: sale.vatAmount,
          at: sale.saleDate,
          customerName: customerName,
          width: shop.paperWidth,
        ),
        mac: shop.printerMac,
      );
}

class _Totals extends StatelessWidget {
  const _Totals({required this.sale});

  final Sale sale;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final balance = sale.total - sale.amountPaid;
    final method = sale.paymentMethod == 'transfer' && sale.transferChannel != null
        ? channelLabel(sale.transferChannel!)
        : channelLabel(sale.paymentMethod);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (sale.discount > 0) ...[
              _Line(label: 'Subtotal', value: sale.subtotal),
              _Line(label: 'Discount', value: -sale.discount),
            ],
            if (sale.vatAmount > 0)
              _Line(label: 'VAT included', value: sale.vatAmount),
            _Line(label: 'Total', value: sale.total, bold: true),
            _Line(label: 'Paid ($method)', value: sale.amountPaid),
            if (balance > 0)
              _Line(label: 'Balance owing', value: balance, color: scheme.error),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
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
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
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

class _ReturnsCard extends StatelessWidget {
  const _ReturnsCard({required this.returns});

  final List<Return> returns;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Returned', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            for (final entry in returns) ...[
              for (final item in ReturnedItem.decodeAll(entry.items))
                Text('${SaleDetailScreen._qty(item.qty)} × ${item.name}'),
              Text(
                [
                  DateFormat('d MMM, h:mm a').format(entry.createdAt),
                  entry.refundMethod == 'debt_credit'
                      ? 'credited ${formatKoboCompact(entry.amount)}'
                      : 'refunded ${formatKoboCompact(entry.amount)} '
                          '(${channelLabel(entry.channel ?? entry.refundMethod)})',
                  entry.restock ? 'back on shelf' : 'written off',
                ].join(' · '),
                style: TextStyle(color: scheme.outline, fontSize: 12),
              ),
              if (entry.reason != null)
                Text(entry.reason!,
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
