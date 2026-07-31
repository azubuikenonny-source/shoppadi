import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../invoices/invoices_screen.dart';
import '../sales/sales_screen.dart';
import '../../core/sync/membership.dart';
import 'backup_screen.dart';
import 'day_close_screen.dart';
import 'printer_screen.dart';
import 'staff_screen.dart';
import 'settings_screen.dart';

/// Everything that is not a daily tab (design doc section 8).
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(shopProfileProvider);
    final shopName = profile.valueOrNull?.name ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: const Text('Shop details'),
            subtitle: Text(shopName.isEmpty
                ? 'Set your shop name for receipts'
                : shopName),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const SettingsScreen(),
            )),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.receipt_outlined),
            title: const Text('Receipts'),
            subtitle: const Text('Find a past sale, re-send it, take returns'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => SalesScreen.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: const Text('Invoices'),
            subtitle: const Text('Bill a customer, chase what is owed'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => InvoicesScreen.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.print_outlined),
            title: const Text('Receipt printer'),
            subtitle: const Text('Pair a Bluetooth printer, test it'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => PrinterScreen.open(context),
          ),
          ListTile(
            leading: const Icon(Icons.point_of_sale_outlined),
            title: const Text('Close day'),
            subtitle: const Text('Count the till, balance every channel'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => DayCloseScreen.open(context),
          ),
          const _StaffTile(),
          const Divider(height: 1),
          const _BackupTile(),
          const Divider(height: 1),
          const _SampleShopTile(),
        ],
      ),
    );
  }
}

/// Who works here. Staff can see the list; only the owner can change it, and
/// the screen itself says so rather than the row vanishing mysteriously.
class _StaffTile extends ConsumerWidget {
  const _StaffTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(membershipProvider).valueOrNull ?? Membership.solo;
    final signedIn = ref.watch(authServiceProvider).isSignedIn;

    return ListTile(
      leading: const Icon(Icons.group_outlined),
      title: const Text('Staff'),
      subtitle: Text(signedIn
          ? (me.canManageStaff
              ? 'Invite a cashier or manager'
              : 'You are signed in as ${me.label.toLowerCase()}')
          : 'Sign in to share this shop with staff'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => StaffScreen.open(context),
    );
  }
}

/// Backup state at a glance, so an owner can see records are safe without
/// opening anything.
class _BackupTile extends ConsumerWidget {
  const _BackupTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authServiceProvider);
    final pending = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final scheme = Theme.of(context).colorScheme;

    final (icon, subtitle, colour) = !auth.isConfigured
        ? (Icons.phone_android, 'Records stay on this phone', scheme.outline)
        : !auth.isSignedIn
            ? (Icons.cloud_off_outlined, 'Sign in to keep a copy safe',
                scheme.tertiary)
            : pending == 0
                ? (Icons.cloud_done_outlined, 'Everything backed up',
                    scheme.primary)
                : (Icons.cloud_queue, '$pending waiting to go up',
                    scheme.tertiary);

    return ListTile(
      leading: Icon(icon, color: colour),
      title: const Text('Cloud backup'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => BackupScreen.open(context),
    );
  }
}

/// Load or clear the sample shop (design doc 4.14).
class _SampleShopTile extends ConsumerStatefulWidget {
  const _SampleShopTile();

  @override
  ConsumerState<_SampleShopTile> createState() => _SampleShopTileState();
}

class _SampleShopTileState extends ConsumerState<_SampleShopTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    await action();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(done)));
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Erase everything?'),
        content: const Text(
            'This deletes all products, sales, customers and debts on this '
            'phone. Use it to clear the sample shop before you start trading.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Erase')),
        ],
      ),
    );
    if (confirmed == true) {
      await _run(ref.read(demoDataProvider).clear, 'All data erased');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasProducts =
        (ref.watch(activeProductsProvider).valueOrNull ?? const []).isNotEmpty;
    // Once a shop is signed in, its records are real and shared with the
    // server. Offering to pour example stock into that is never what anyone
    // wants, so the showroom is only on offer before the shop opens.
    final signedIn = ref.watch(authServiceProvider).isSignedIn;

    if (!hasProducts && signedIn) {
      return const ListTile(
        leading: Icon(Icons.science_outlined),
        title: Text('Try a sample shop'),
        subtitle: Text('Not while signed in — sample stock is not yours'),
        enabled: false,
      );
    }

    return ListTile(
      leading: _busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(hasProducts ? Icons.delete_outline : Icons.science_outlined),
      title: Text(hasProducts ? 'Erase all data' : 'Try a sample shop'),
      subtitle: Text(hasProducts
          ? 'Start fresh for your real shop'
          : 'Fills the app with example products and two weeks of sales'),
      enabled: !_busy,
      onTap: _busy
          ? null
          : hasProducts
              ? _confirmClear
              : () => _run(ref.read(demoDataProvider).load,
                  'Sample shop loaded — have a look around'),
    );
  }
}
