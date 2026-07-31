import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/money.dart';
import '../../core/providers.dart';
import 'cart.dart';
import 'checkout_sheet.dart';

/// The ten-second sale (design doc 4.1): search, tap, charge.
class SellScreen extends ConsumerStatefulWidget {
  const SellScreen({super.key});

  @override
  ConsumerState<SellScreen> createState() => _SellScreenState();
}

class _SellScreenState extends ConsumerState<SellScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = ref.watch(activeProductsProvider);
    final cart = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell'),
        actions: [
          if (cart.isNotEmpty)
            TextButton(
              onPressed: () => ref.read(cartProvider.notifier).clear(),
              child: const Text('Clear'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search products…',
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
            child: products.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Could not load products: $e')),
              data: (all) {
                final items = _query.isEmpty
                    ? all
                    : all
                        .where((p) => p.name.toLowerCase().contains(_query))
                        .toList();
                if (all.isEmpty) {
                  return _Empty(
                    icon: Icons.storefront_outlined,
                    title: 'No products yet',
                    subtitle: 'Add products in Inventory to start selling.',
                  );
                }
                if (items.isEmpty) {
                  return _Empty(
                    icon: Icons.search_off,
                    title: 'Nothing matches "$_query"',
                    subtitle: 'Try a shorter search.',
                  );
                }
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 200,
                    childAspectRatio: 1.5,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final inCart = cart
                        .where((e) => e.product.id == items[i].id)
                        .fold<double>(0, (_, e) => e.qty);
                    return _ProductCard(
                      product: items[i],
                      inCart: inCart,
                      onTap: () =>
                          ref.read(cartProvider.notifier).add(items[i]),
                      onRemoveOne: () => ref
                          .read(cartProvider.notifier)
                          .setQty(items[i].id, inCart - 1),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: cart.isEmpty
                ? null
                : () => CheckoutSheet.show(context),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(cart.isEmpty
                ? 'Charge ${formatKoboCompact(0)}'
                : 'Charge ${formatKoboCompact(total)}  ·  ${cart.length} item${cart.length == 1 ? '' : 's'}'),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.inCart,
    required this.onTap,
    required this.onRemoveOne,
  });

  final Product product;
  final double inCart;
  final VoidCallback onTap;

  /// Undo one tap. Miscounting at a busy counter is normal, and the fix has to
  /// be where the thumb already is — not behind the checkout sheet, and
  /// certainly not "clear the whole sale and start again".
  final VoidCallback onRemoveOne;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outOfStock = product.quantity <= 0;

    return Card(
      color: inCart > 0 ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(formatKoboCompact(product.sellingPrice),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (inCart > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Sits inside the card's own tap target, so it needs a
                        // generous touch area of its own or a thumb aiming to
                        // subtract will add instead.
                        InkWell(
                          onTap: onRemoveOne,
                          customBorder: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(Icons.remove_circle_outline,
                                size: 20, color: scheme.primary),
                          ),
                        ),
                        const SizedBox(width: 2),
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: scheme.primary,
                          child: Text(
                            inCart.toStringAsFixed(0),
                            style: TextStyle(
                                fontSize: 11,
                                color: scheme.onPrimary,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    )
                  else if (outOfStock)
                    Text('Out',
                        style: TextStyle(fontSize: 11, color: scheme.error)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: scheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: scheme.outline)),
        ],
      ),
    );
  }
}
