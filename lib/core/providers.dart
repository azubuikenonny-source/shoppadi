import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'db/customers_repository.dart';
import 'db/database.dart';
import 'db/day_close_repository.dart';
import 'db/demo_data.dart';
import 'db/invoices_repository.dart';
import 'printing/printer_service.dart';
import 'sync/auth_service.dart';
import 'sync/membership.dart';
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

/// Fires on every real Supabase auth event — sign in, sign out, token
/// refresh. This is what businessIdProvider must react to, not a manual
/// invalidate() called right after signInWithGoogle(): that future resolves
/// the instant the browser launches, long before the user finishes logging
/// in, so invalidating there races the real sign-in and loses every time.
final authStateProvider = StreamProvider<void>((ref) {
  final changes = ref.watch(authServiceProvider).changes;
  return changes == null ? const Stream.empty() : changes.map((_) {});
});

/// The shop id on the server, once signed in and belonging somewhere. Stored
/// locally so the app knows which business to stamp on rows without a round
/// trip, and so it still knows with no signal.
///
/// Never creates a shop on its own — see [AuthService.createMyShop].
final businessIdProvider = FutureProvider<String?>((ref) async {
  final settings = ref.watch(settingsRepoProvider);
  final stored = await settings.businessId();
  if (stored != null && stored.isNotEmpty) return stored;

  final membership = await ref.watch(membershipProvider.future);
  final id = membership.businessId;
  if (id != null) await settings.saveBusinessId(id);
  return id;
});

/// What the person holding this phone is allowed to do.
///
/// Asks the server when it can and remembers the answer, because permissions
/// have to hold offline. Falls back to owner only when nobody has ever signed
/// in — an unshared phone holding its own records answers to itself.
final membershipProvider = FutureProvider<Membership>((ref) async {
  ref.watch(authStateProvider);

  final auth = ref.watch(authServiceProvider);
  final settings = ref.watch(settingsRepoProvider);

  if (!auth.isSignedIn) {
    final (cachedRole, _) = await settings.cachedMembership();
    // Signed out but previously staff: stay restricted rather than silently
    // handing a cashier the owner's view by signing out.
    if (cachedRole != null && cachedRole != 'owner') {
      return Membership(role: Membership.roleFrom(cachedRole));
    }
    return Membership.solo;
  }

  try {
    final fresh = await auth.fetchMembership();
    if (fresh != null) {
      await settings.saveMembership(
          fresh.role.name, fresh.canSeeProfitFlag);
      return fresh;
    }
  } on Object {
    // Offline or the server said no — fall through to what we last knew.
  }

  final (cachedRole, seesProfit) = await settings.cachedMembership();
  return cachedRole == null
      ? Membership.solo
      : Membership(
          role: Membership.roleFrom(cachedRole),
          canSeeProfitFlag: seesProfit,
        );
});

/// Convenience for widgets: never null, defaults to the safest answer while
/// the real one is still loading.
final canSeeProfitProvider = Provider<bool>((ref) =>
    ref.watch(membershipProvider).valueOrNull?.canSeeProfit ?? false);

final staffProvider = FutureProvider<List<StaffMember>>((ref) async {
  ref.watch(authStateProvider);
  return ref.watch(authServiceProvider).listStaff();
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final businessId = ref.watch(businessIdProvider).valueOrNull;
  final engine = SyncEngine(db: ref.watch(dbProvider), businessId: businessId);
  ref.onDispose(engine.dispose);
  // Only worth running the timer once there is a business to sync against —
  // this fires again automatically the moment sign-in actually completes,
  // because businessIdProvider re-resolving rebuilds this provider fresh.
  if (businessId != null) engine.start();
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
