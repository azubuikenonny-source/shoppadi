import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/database.dart';
import 'package:shoppadi/features/sell/cart.dart';

Product _product({required String id, required int price}) => Product(
      id: id,
      name: 'Product $id',
      baseUnit: 'piece',
      costPrice: price ~/ 2,
      sellingPrice: price,
      quantity: 20,
      lowStockLevel: 0,
      vatExempt: false,
      isActive: true,
      updatedAt: DateTime(2026, 7, 25),
    );

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  CartNotifier notifier() => container.read(cartProvider.notifier);
  int total() => container.read(cartTotalProvider);

  test('starts empty', () {
    expect(container.read(cartProvider), isEmpty);
    expect(total(), 0);
  });

  test('adding the same product twice increments quantity, not lines', () {
    final milk = _product(id: 'milk', price: 150000);
    notifier().add(milk);
    notifier().add(milk);

    final cart = container.read(cartProvider);
    expect(cart, hasLength(1));
    expect(cart.single.qty, 2);
    expect(total(), 300000);
  });

  test('total sums across different products', () {
    notifier().add(_product(id: 'milk', price: 150000));
    notifier().add(_product(id: 'bread', price: 90000));

    expect(container.read(cartProvider), hasLength(2));
    expect(total(), 240000);
  });

  test('setting quantity to zero removes the line', () {
    notifier().add(_product(id: 'milk', price: 150000));
    notifier().setQty('milk', 0);

    expect(container.read(cartProvider), isEmpty);
    expect(total(), 0);
  });

  test('clear empties the cart', () {
    notifier().add(_product(id: 'milk', price: 150000));
    notifier().add(_product(id: 'bread', price: 90000));
    notifier().clear();

    expect(container.read(cartProvider), isEmpty);
  });

  test('undo after Clear brings the exact sale back', () {
    final milk = _product(id: 'milk', price: 150000);
    notifier().add(milk);
    notifier().add(milk);
    notifier().add(_product(id: 'bread', price: 90000));

    final wiped = List.of(container.read(cartProvider));
    notifier().clear();
    expect(container.read(cartProvider), isEmpty);

    notifier().restore(wiped);
    final cart = container.read(cartProvider);
    expect(cart, hasLength(2));
    expect(cart.first.qty, 2);
    expect(total(), 390000);
  });
}
