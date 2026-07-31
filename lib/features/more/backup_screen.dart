import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/sync/sync_engine.dart';

/// Cloud backup: sign in, see what is still waiting to go up, push it now
/// (design doc 4.11). The app never requires any of this to keep trading.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const BackupScreen()));

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startOwnShop() => _run(() async {
        final profile = await ref.read(settingsRepoProvider).load();
        await ref
            .read(authServiceProvider)
            .createMyShop(shopName: profile.name);
        ref.invalidate(membershipProvider);
        ref.invalidate(businessIdProvider);
      });

  Future<void> _joinWithCode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinCodeDialog(),
    );
    if (code == null || code.trim().isEmpty) return;

    await _run(() async {
      await ref.read(authServiceProvider).redeemInvite(code);
      ref.invalidate(membershipProvider);
      ref.invalidate(businessIdProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authServiceProvider);
    final status = ref.watch(syncStatusProvider).valueOrNull;
    final pending = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
    final businessId = ref.watch(businessIdProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Cloud backup')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(
            status: status,
            pending: pending,
            signedIn: auth.isSignedIn,
            configured: auth.isConfigured,
          ),
          const SizedBox(height: 20),
          if (!auth.isConfigured)
            Text(
              'This copy of the app was built without cloud settings, so '
              'everything stays on this phone. That is safe to use — records '
              'are only at risk if the phone is lost.',
              style: TextStyle(color: scheme.outline),
            )
          else if (!auth.isSignedIn) ...[
            Text('Sign in to keep a copy off this phone',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone number',
                hintText: '08031234567',
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Six-digit code',
                  helperText: 'Sent by SMS',
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        if (!_codeSent) {
                          await ref
                              .read(authServiceProvider)
                              .sendOtp(_phone.text);
                          if (mounted) setState(() => _codeSent = true);
                        } else {
                          await ref.read(authServiceProvider).verifyOtp(
                              phone: _phone.text, code: _code.text);
                          // No manual invalidate needed: verifyOtp completing
                          // fires a real Supabase auth event, which
                          // businessIdProvider now reacts to directly.
                        }
                      }),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text(_codeSent ? 'Confirm code' : 'Send me a code'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        // This future resolves once the browser launches, not
                        // once the user finishes signing in — that happens
                        // later via the OAuth redirect, which fires a real
                        // Supabase auth event businessIdProvider reacts to.
                        await ref.read(authServiceProvider).signInWithGoogle();
                      }),
              icon: const Icon(Icons.g_mobiledata, size: 24),
              label: const Text('Continue with Google'),
            ),
          ] else if (businessId == null) ...[
            // Signed in but belonging nowhere. Asking rather than assuming is
            // what lets a cashier join their employer instead of silently
            // getting a shop of their own they can never leave.
            Text('Is this your shop, or are you joining one?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _startOwnShop,
              icon: const Icon(Icons.storefront_outlined),
              label: const Text('This is my own shop'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _joinWithCode,
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Join with a code'),
            ),
            const SizedBox(height: 12),
            Text(
              'Joining needs a six-character code from the shop owner. They '
              'make one under More → Staff.',
              style: TextStyle(color: scheme.outline, fontSize: 12),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.verified_user_outlined, color: scheme.primary),
              title: Text(auth.currentUser?.phone ??
                  auth.currentUser?.email ??
                  'Signed in'),
              subtitle: const Text('This shop is backing up'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run(() => ref.read(syncEngineProvider).syncNow()),
              icon: const Icon(Icons.cloud_upload_outlined),
              label: Text(pending == 0 ? 'Check for changes' : 'Back up now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(() async {
                        await ref.read(authServiceProvider).signOut();
                        ref.invalidate(businessIdProvider);
                      }),
              child: const Text('Sign out'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_error!,
                  style: TextStyle(color: scheme.onErrorContainer)),
            ),
          ],
          const SizedBox(height: 28),
          Text('What gets backed up',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Every sale, product, customer, debt, return, till count and '
            'invoice. Nothing is deleted from this phone when it goes up — the '
            'copy on the server is a second home for it, not a move.',
            style: TextStyle(color: scheme.outline),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.pending,
    required this.signedIn,
    required this.configured,
  });

  final SyncStatus? status;
  final int pending;
  final bool signedIn;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phase = status?.phase ??
        (!configured
            ? SyncPhase.notConfigured
            : signedIn
                ? SyncPhase.idle
                : SyncPhase.notSignedIn);

    final (icon, color) = switch (phase) {
      SyncPhase.idle when pending == 0 => (Icons.cloud_done_outlined, scheme.primary),
      SyncPhase.idle => (Icons.cloud_queue, scheme.tertiary),
      SyncPhase.syncing => (Icons.cloud_sync_outlined, scheme.primary),
      SyncPhase.restoring => (Icons.cloud_download_outlined, scheme.primary),
      SyncPhase.offline => (Icons.cloud_off_outlined, scheme.tertiary),
      SyncPhase.error => (Icons.error_outline, scheme.error),
      SyncPhase.notSignedIn => (Icons.cloud_off_outlined, scheme.outline),
      SyncPhase.notConfigured => (Icons.phone_android, scheme.outline),
    };

    final synced = status?.lastSyncedAt;
    final restored = status?.restored ?? 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      status?.label ??
                          SyncStatus(phase: phase, pending: pending).label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 16)),
                  if (synced != null)
                    Text('Last backed up ${DateFormat.Hm().format(synced)}',
                        style: TextStyle(color: scheme.outline, fontSize: 12)),
                  // Only worth saying when something actually came down, which
                  // in practice means a phone that just restored a shop.
                  if (restored > 0)
                    Text(
                        '$restored record${restored == 1 ? '' : 's'} '
                        'brought down from the cloud',
                        style:
                            TextStyle(color: scheme.primary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Owns its controller, so the field cannot outlive it during the dialog's
/// exit animation — see prompt_dialogs.dart for why that matters.
class _JoinCodeDialog extends StatefulWidget {
  const _JoinCodeDialog();

  @override
  State<_JoinCodeDialog> createState() => _JoinCodeDialogState();
}

class _JoinCodeDialogState extends State<_JoinCodeDialog> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_code.text.trim().toUpperCase());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Join a shop'),
      content: TextField(
        controller: _code,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        maxLength: 6,
        onSubmitted: (_) => _submit(),
        style: const TextStyle(fontSize: 24, letterSpacing: 6),
        decoration: const InputDecoration(
          labelText: 'Six-character code',
          helperText: 'From the shop owner',
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Join')),
      ],
    );
  }
}
