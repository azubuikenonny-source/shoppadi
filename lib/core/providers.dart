import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/customers_repository.dart';
import 'db/database.dart';
import 'db/day_close_repository.dart';
import 'db/demo_data.dart';
import 'db/invoices_repository.dart';
import 'printing/printer_service.dart';
import 'sync/auth_service.dart';
import 'sync/sync_engine.dart';
import 'db/products_repository.dart';
import 'db/reports_repository.dart';
import 'db/returns_repository.dart';
import 'db/sales_repository.dart';
import 'db/settings_repository.dart';

/// Riverpod is lazy: nothing below is created until a widget reads it, which
/// lets tests override the stream providers and never open a real database.
final dbProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final productsRepoProvider = Provider<ProductsRepository>(
    (ref) => ProductsRepository(ref.watch(dbProvider)));

final customersRepoProvider = Provider<CustomersRepository>(
    (ref) => CustomersRepository(ref.watch(dbProvider)));

final salesRepoProvider =
    Provider<SalesRepository>((ref) => SalesRepository(ref.watch(dbProvider)));

final activeProductsProvider = StreamProvider<List<Product>>(
    (ref) => ref.watch(productsRepoProvider).watchActive());

final customersProvider = StreamProvider<List<Customer>>(
    (ref) => ref.watch(customersRepoProvider).watchAll());

final reportsRepoProvider = Provider<ReportsRepository>(
    (ref) => ReportsRepository(ref.watch(dbProvider)));

final debtorsProvider = StreamProvider<List<Debtor>>(
    (ref) => ref.watch(customersRepoProvider).watchDebtors());

final dashboardProvider = StreamProvider<DashboardData>(
    (ref) => ref.watch(reportsRepoProvider).watchDashboard());

final settingsRepoProvider = Provider<SettingsRepository>(
    (ref) => SettingsRepository(ref.watch(dbProvider)));

final shopProfileProvider = StreamProvider<ShopProfile>(
    (ref) => ref.watch(settingsRepoProvider).watchProfile());

final demoDataProvider =
    Provider<DemoData>((ref) => DemoData(ref.watch(dbProvider)));

final dayCloseRepoProvider = Provider<DayCloseRepository>(
    (ref) => DayCloseRepository(ref.watch(dbProvider)));

final todayTakingsProvider = StreamProvider<DayTakings>(
    (ref) => ref.watch(dayCloseRepoProvider).watchTakings(DateTime.now()));

final todayCloseProvider = StreamProvider<DayClose?>(
    (ref) => ref.watch(dayCloseRepoProvider).watchClose(DateTime.now()));

final closeHistoryProvider = StreamProvider<List<DayClose>>(
    (ref) => ref.watch(dayCloseRepoProvider).watchHistory());

final returnsRepoProvider = Provider<ReturnsRepository>(
    (ref) => ReturnsRepository(ref.watch(dbProvider)));

final recentSalesProvider = StreamProvider<List<SaleSummary>>(
    (ref) => ref.watch(salesRepoProvider).watchRecentSales());

final saleProvider = StreamProvider.family<Sale?, String>(
    (ref, saleId) => ref.watch(returnsRepoProvider).watchSale(saleId));

final saleLinesProvider = StreamProvider.family<List<SaleLine>, String>(
    (ref, saleId) => ref.watch(returnsRepoProvider).watchLines(saleId));

final saleReturnsProvider = StreamProvider.family<List<Return>, String>(
    (ref, saleId) => ref.watch(returnsRepoProvider).watchReturns(saleId));

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// The shop id on the server, once signed in. Stored locally so the app knows
/// which business to stamp on rows without a round trip.
final businessIdProvider = FutureProvider<String?>((ref) async {
  final settings = ref.watch(settingsRepoProvider);
  final stored = await settings.businessId();
  if (stored != null && stored.isNotEmpty) return stored;

  final auth = ref.watch(authServiceProvider);
  if (!auth.isSignedIn) return null;

  final profile = await settings.load();
  final id = await auth.ensureBusiness(shopName: profile.displayName);
  if (id != null) await settings.saveBusinessId(id);
  return id;
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(
    db: ref.watch(dbProvider),
    businessId: ref.watch(businessIdProvider).valueOrNull,
  );
  ref.onDispose(engine.dispose);
  return engine;
});

final syncStatusProvider = StreamProvider<SyncStatus>(
    (ref) => ref.watch(syncEngineProvider).status);

/// How many local changes have not reached the server yet.
final pendingSyncCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(dbProvider);
  return db.select(db.outbox).watch().map((rows) => rows.length);
});

final printerServiceProvider = Provider<PrinterService>((ref) {
  final service = PrinterService();
  ref.onDispose(service.disconnect);
  return service;
});

final invoicesRepoProvider = Provider<InvoicesRepository>(
    (ref) => InvoicesRepository(ref.watch(dbProvider)));

final invoicesProvider = StreamProvider<List<Invoice>>(
    (ref) => ref.watch(invoicesRepoProvider).watchAll());

final invoiceProvider = StreamProvider.family<Invoice?, String>(
    (ref, id) => ref.watch(invoicesRepoProvider).watch(id));
