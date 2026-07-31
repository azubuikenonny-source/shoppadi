import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/customers/customers_screen.dart';
import 'features/insights/insights_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/more/more_screen.dart';
import 'features/sell/sell_screen.dart';

// Injected at build time:
// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
    await Supabase.initialize(
        url: _supabaseUrl, publishableKey: _supabaseAnonKey);
  }
  runApp(const ProviderScope(child: ShopPadiApp()));
}

class ShopPadiApp extends StatelessWidget {
  const ShopPadiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ShopPadi',
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  static const _screens = [
    SellScreen(),
    InventoryScreen(),
    CustomersScreen(),
    InsightsScreen(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // Holds the sync engine open for as long as the app is. Riverpod builds a
    // provider only when something reads it, and the only reader used to be
    // the Cloud backup screen — so syncing ran while that screen was open and
    // stopped the moment it closed. An owner never saw what their staff had
    // done unless they happened to be sitting on the backup screen.
    ref.watch(syncBootstrapProvider);

    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.point_of_sale_outlined),
              selectedIcon: Icon(Icons.point_of_sale),
              label: 'Sell'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Inventory'),
          NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people),
              label: 'Customers'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Insights'),
          NavigationDestination(
              icon: Icon(Icons.menu_outlined),
              selectedIcon: Icon(Icons.menu),
              label: 'More'),
        ],
      ),
    );
  }
}
