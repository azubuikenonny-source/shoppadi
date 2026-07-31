import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import 'product_form_sheet.dart';
import 'stock_in_sheet.dart';

/// Products, stock levels, low-stock flags (design doc 4.2).
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(activeProductsProvider);
    final me = ref.watch(membershipProvider).valueOrNull;
    // Default to the restricted view until the real answer arrives, so a
    // cashier never glimpses cost prices during a slow lookup.
    final canManage = me?.canManageStock ?? false;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: products.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load products: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 56, color: scheme.outline),
                  const SizedBox(height: 12),
                  Text('No products yet',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Tap + to add your first product.',
                      style: TextStyle(color: scheme.outline)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 88),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) =>
                _ProductTile(product: items[i], canManage: canManage),
          );
        },
      ),
      floatingActionButton: canManage
          ? FloatingActionButton(
              onPressed: () => ProductFormSheet.show(context),
              tooltip: 'Add product',
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.canManage});

  final Product product;

  /// Cashiers see the shelf: what it is, what it sells for, how many are left.
  /// Stocking in and editing prices belong to a manager.
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Stock can go below zero: the app never blocks a sale at the counter just
    // because the records disagree. A negative number means goods left the shop
    // that were never booked in, so it asks for a recount rather than showing
    // a baffling "-15 left".
    final oversold = product.quantity < 0;
    final isOut = product.quantity <= 0;
    final isLow = !isOut &&
        product.lowStockLevel > 0 &&
        product.quantity <= product.lowStockLevel;

    final (stockText, stockColour) = oversold
        ? ('${(-product.quantity).toStringAsFixed(0)} sold beyond stock',
            scheme.error)
        : isOut
            ? ('none left', scheme.error)
            : isLow
                ? ('${product.quantity.toStringAsFixed(0)} left', scheme.tertiary)
                : ('${product.quantity.toStringAsFixed(0)} left', scheme.outline);

    return ListTile(
      title: Text(product.name),
      subtitle: Row(
        children: [
          Text(formatKoboCompact(product.sellingPrice)),
          const SizedBox(width: 8),
          Text('·', style: TextStyle(color: scheme.outline)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(stockText,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: stockColour,
                  fontWeight: (isLow || isOut) ? FontWeight.w600 : null,
                )),
          ),
          if (oversold) ...[
            const SizedBox(width: 8),
            _Chip(label: 'Recount', color: scheme.error),
          ] else if (isOut) ...[
            const SizedBox(width: 8),
            _Chip(label: 'Out of stock', color: scheme.error),
          ] else if (isLow) ...[
            const SizedBox(width: 8),
            _Chip(label: 'Low', color: scheme.tertiary),
          ],
        ],
      ),
      trailing: canManage
          ? IconButton(
              icon: const Icon(Icons.add_box_outlined),
              tooltip: 'Stock in',
              onPressed: () => StockInSheet.show(context, product),
            )
          : null,
      onTap: canManage
          ? () => ProductFormSheet.show(context, product: product)
          : null,
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
