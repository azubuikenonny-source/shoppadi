import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/channels.dart';
import '../../core/db/database.dart';
import '../../core/db/returns_repository.dart';
import '../../core/money.dart';
import '../../core/providers.dart';

/// Taking goods back (design doc 4.13): pick the lines, decide whether the
/// stock is resellable, then refund the money or knock it off what they owe.
class ReturnSheet extends ConsumerStatefulWidget {
  const ReturnSheet({super.key, required this.saleId, required this.sale});

  final String saleId;
  final Sale sale;

  static Future<void> show(
    BuildContext context, {
    required String saleId,
    required Sale sale,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ReturnSheet(saleId: saleId, sale: sale),
    );
  }

  @override
  ConsumerState<ReturnSheet> createState() => _ReturnSheetState();
}

class _ReturnSheetState extends ConsumerState<ReturnSheet> {
  final _qty = <String, double>{};
  final _reason = TextEditingController();
  bool _restock = true;
  late String _refundMethod;
  String _channel = 'opay';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Nothing was paid, so there is no money to hand back — the only sensible
    // refund is to reduce what they owe.
    _refundMethod = widget.sale.amountPaid > 0 ? 'cash' : 'debt_credit';
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _hasSelection => _qty.values.any((q) => q > 0);

  /// Pre-discount value of the selected goods.
  int _grossFor(List<SaleLine> lines) {
    var gross = 0;
    for (final line in lines) {
      final qty = _qty[line.item.id] ?? 0;
      if (qty > 0) gross += (qty * line.item.unitPrice).round();
    }
    return gross;
  }

  Future<void> _submit() async {
    setState(() => _saving = true);

    final refunded = await ref.read(returnsRepoProvider).recordReturn(
          saleId: widget.saleId,
          qtyBySaleItem: Map.of(_qty)..removeWhere((_, q) => q <= 0),
          restock: _restock,
          refundMethod: _refundMethod,
          channel: _refundMethod == 'transfer' ? _channel : null,
          reason: _reason.text,
        );

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(_refundMethod == 'debt_credit'
          ? '${formatKoboCompact(refunded)} taken off their balance'
          : '${formatKoboCompact(refunded)} refunded'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(saleLinesProvider(widget.saleId));
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, insets + 16),
      child: lines.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Text('Could not load the items: $e'),
        data: (list) {
          final gross = _grossFor(list);
          final maths = ReturnMaths.from(
            oldSubtotal: widget.sale.subtotal,
            oldDiscount: widget.sale.discount,
            oldVat: widget.sale.vatAmount,
            oldTotal: widget.sale.total,
            returnedGross: gross,
          );

          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Return items',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('How many of each is coming back?',
                    style: TextStyle(color: scheme.outline)),
                const SizedBox(height: 12),
                for (final line in list)
                  _LinePicker(
                    line: line,
                    selected: _qty[line.item.id] ?? 0,
                    onChanged: (q) =>
                        setState(() => _qty[line.item.id] = q),
                  ),
                const Divider(height: 24),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _restock,
                  onChanged: (v) => setState(() => _restock = v),
                  title: Text(_restock
                      ? 'Put back on the shelf'
                      : 'Written off as damaged'),
                  subtitle: Text(_restock
                      ? 'Stock goes back up and can be sold again'
                      : 'Recorded as a loss — stock stays down'),
                ),
                const SizedBox(height: 8),
                Text('Refund', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final option in const {
                      'cash': 'Cash back',
                      'transfer': 'Transfer back',
                      'debt_credit': 'Off their balance',
                    }.entries)
                      ChoiceChip(
                        label: Text(option.value),
                        selected: _refundMethod == option.key,
                        onSelected: (_) =>
                            setState(() => _refundMethod = option.key),
                      ),
                  ],
                ),
                if (widget.sale.amountPaid == 0 && _refundMethod != 'debt_credit')
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'This sale was never paid for, so there is nothing to '
                      'hand back — the balance will simply drop.',
                      style: TextStyle(color: scheme.tertiary, fontSize: 12),
                    ),
                  ),
                if (_refundMethod == 'transfer') ...[
                  const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Reason',
                    hintText: 'Wrong size, expired, changed mind…',
                  ),
                ),
                if (_hasSelection) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            _refundMethod == 'debt_credit'
                                ? 'Coming off their balance'
                                : 'To hand back',
                            style: TextStyle(color: scheme.onPrimaryContainer)),
                        Text(formatKoboCompact(maths.refund),
                            style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: (_saving || !_hasSelection) ? null : _submit,
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: Text(_hasSelection
                      ? 'Confirm return'
                      : 'Choose what is coming back'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LinePicker extends StatelessWidget {
  const _LinePicker({
    required this.line,
    required this.selected,
    required this.onChanged,
  });

  final SaleLine line;
  final double selected;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final max = line.item.qty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.productName),
                Text('${_fmt(max)} sold at ${formatKoboCompact(line.item.unitPrice)}',
                    style: TextStyle(color: scheme.outline, fontSize: 12)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline),
            onPressed:
                selected <= 0 ? null : () => onChanged(selected - 1),
          ),
          SizedBox(
            width: 24,
            child: Text(_fmt(selected),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: selected > 0 ? scheme.primary : scheme.outline)),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline),
            onPressed:
                selected >= max ? null : () => onChanged(selected + 1),
          ),
        ],
      ),
    );
  }

  static String _fmt(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();
}
