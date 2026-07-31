import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/database.dart';
import 'package:shoppadi/core/db/reports_repository.dart';
import 'package:shoppadi/core/db/settings_repository.dart';
import 'package:shoppadi/core/providers.dart';
import 'package:shoppadi/main.dart';

/// Overriding the stream providers keeps the real database out of widget
/// tests — Riverpod never builds dbProvider if nothing reads it. The shell
/// uses an IndexedStack, so every tab is built and every provider it reads
/// must be covered here.
List<Override> _overrides({List<Product> products = const []}) => [
      activeProductsProvider.overrideWith((ref) => Stream.value(products)),
      customersProvider.overrideWith((ref) => Stream.value(const [])),
      debtorsProvider.overrideWith((ref) => Stream.value(const [])),
      dashboardProvider.overrideWith((ref) => Stream.value(const DashboardData(
            today: PeriodSummary.empty,
            week: PeriodSummary.empty,
            month: PeriodSummary.empty,
            totalOwed: 0,
          ))),
      shopProfileProvider
          .overrideWith((ref) => Stream.value(const ShopProfile())),
      // The More tab shows a backup status chip, which would otherwise open
      // the real database just to count the outbox.
      pendingSyncCountProvider.overrideWith((ref) => Stream.value(0)),
    ];

void main() {
  testWidgets('shell shows all five tabs', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: const ShopPadiApp(),
    ));
    await tester.pump();

    expect(find.text('Sell'), findsWidgets); // tab label + app bar title
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('empty shop prompts for products', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(),
      child: const ShopPadiApp(),
    ));
    await tester.pump();

    expect(find.text('Add products in Inventory to start selling.'),
        findsOneWidget);
  });

  testWidgets('tapping a product adds it to the cart', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: _overrides(products: [testProduct(name: 'Peak Milk', price: 150000)]),
      child: const ShopPadiApp(),
    ));
    await tester.pump();

    expect(find.text('Charge ₦0'), findsOneWidget);

    await tester.tap(find.text('Peak Milk'));
    await tester.pump();

    expect(find.text('Charge ₦1,500  ·  1 item'), findsOneWidget);
  });

  testWidgets('a miscount can be corrected without clearing the sale',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides:
          _overrides(products: [testProduct(name: 'Peak Milk', price: 150000)]),
      child: const ShopPadiApp(),
    ));
    await tester.pump();

    // Meant to ring up four, tapped five — what actually happens at a counter.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Peak Milk'));
      await tester.pump();
    }
    expect(find.text('Charge ₦7,500  ·  1 item'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();

    expect(find.text('Charge ₦6,000  ·  1 item'), findsOneWidget);
  });

  testWidgets('removing the last one takes the item off the sale',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides:
          _overrides(products: [testProduct(name: 'Peak Milk', price: 150000)]),
      child: const ShopPadiApp(),
    ));
    await tester.pump();

    await tester.tap(find.text('Peak Milk'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();

    expect(find.text('Charge ₦0'), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
  });
}

Product testProduct({
  String id = 'p1',
  String name = 'Test product',
  int price = 100000,
  int cost = 60000,
  double quantity = 10,
}) =>
    Product(
      id: id,
      name: name,
      baseUnit: 'piece',
      costPrice: cost,
      sellingPrice: price,
      quantity: quantity,
      lowStockLevel: 0,
      vatExempt: false,
      isActive: true,
      updatedAt: DateTime(2026, 7, 25),
    );
