import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/money.dart';
import '../../core/providers.dart';

/// Stock in (new purchase) or a counted correction. Both write a movement row;
/// nothing ever edits quantity directly.
class StockInSheet extends ConsumerStatefulWidget {
  const StockInSheet({super.key, required this.product});

  final Product product;

  static Future<void> show(BuildContext context, Product product) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StockInSheet(product: product),
    );
  }

  @override
  ConsumerState<StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends ConsumerState<StockInSheet> {
  final _qty = TextEditingController();
  final _cost = TextEditingController();
  final _reason = TextEditingController();
  bool _isCorrection = false;

  /// A bounced tap must not write the purchase twice. Every ledger entry here
  /// is permanent by design, so a double-fire is not an annoyance — it is
  /// forty phantom cartons on the shelf.
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _cost.text = (widget.product.costPrice / 100).toStringAsFixed(2);
  }

  @override
  void dispose() {
    _qty.dispose();
    _cost.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final qty = double.tryParse(_qty.text.trim());
    if (qty == null || qty == 0) return;
    setState(() => _busy = true);
    final repo = ref.read(productsRepoProvider);

    if (_isCorrection) {
      await repo.adjustStock(
        productId: widget.product.id,
        delta: qty,
        reason: _reason.text.trim().isEmpty ? 'Count correction' : _reason.text.trim(),
      );
    } else {
      await repo.receiveStock(
        productId: widget.product.id,
        qty: qty,
        unitCost: parseNairaToKobo(_cost.text),
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, insets + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.product.name,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('In stock: ${widget.product.quantity.toStringAsFixed(0)}',
              style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 16),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Stock in')),
              ButtonSegment(value: true, label: Text('Correction')),
            ],
            selected: {_isCorrection},
            onSelectionChanged: (s) => setState(() => _isCorrection = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
                decimal: true, signed: true),
            decoration: InputDecoration(
              labelText: _isCorrection ? 'Adjust by' : 'Quantity received',
              helperText: _isCorrection ? 'Use -5 for losses' : null,
            ),
          ),
          const SizedBox(height: 12),
          if (_isCorrection)
            TextField(
              controller: _reason,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Damaged, miscount, theft…',
              ),
            )
          else
            TextField(
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cost per unit',
                prefixText: '₦',
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(_isCorrection ? 'Save correction' : 'Add to stock'),
          ),
        ],
      ),
    );
  }
}
