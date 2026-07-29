import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';

/// One product in the cart, at the price showing when it was added.
class CartEntry {
  const CartEntry({required this.product, required this.qty});

  final Product product;
  final double qty;

  int get lineTotal => (qty * product.sellingPrice).round();

  CartEntry copyWith({double? qty}) =>
      CartEntry(product: product, qty: qty ?? this.qty);
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartEntry>>(CartNotifier.new);

class CartNotifier extends Notifier<List<CartEntry>> {
  @override
  List<CartEntry> build() => const [];

  void add(Product product, {double qty = 1}) {
    final index = state.indexWhere((e) => e.product.id == product.id);
    if (index == -1) {
      state = [...state, CartEntry(product: product, qty: qty)];
    } else {
      setQty(product.id, state[index].qty + qty);
    }
  }

  void setQty(String productId, double qty) {
    if (qty <= 0) {
      remove(productId);
      return;
    }
    state = [
      for (final e in state)
        if (e.product.id == productId) e.copyWith(qty: qty) else e,
    ];
  }

  void remove(String productId) =>
      state = state.where((e) => e.product.id != productId).toList();

  void clear() => state = const [];
}

final cartTotalProvider = Provider<int>((ref) => ref
    .watch(cartProvider)
    .fold<int>(0, (sum, entry) => sum + entry.lineTotal));
