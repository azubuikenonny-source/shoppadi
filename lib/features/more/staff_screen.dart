import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/sync/membership.dart';

/// Who works here and what they can see (design doc section 6).
class StaffScreen extends ConsumerStatefulWidget {
  const StaffScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const StaffScreen()));

  @override
  ConsumerState<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends ConsumerState<StaffScreen> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(membershipProvider).valueOrNull ?? Membership.solo;
    final auth = ref.watch(authServiceProvider);
    final staff = ref.watch(staffProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Staff')),
      body: !auth.isConfigured || !auth.isSignedIn
          ? _Explain(
              icon: Icons.cloud_off_outlined,
              title: 'Sign in first',
              body: 'Staff share a shop through the cloud, so the shop needs '
                  'to be signed in before anyone can join it.',
              colour: scheme.outline,
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                staff.when(
                  loading: () => const Center(
                      child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator())),
                  error: (e, _) => _Explain(
                    icon: Icons.error_outline,
                    title: 'Could not load the team',
                    body: '$e',
                    colour: scheme.error,
                  ),
                  data: (list) => Column(
                    children: [
                      for (final person in list)
                        _StaffTile(
                          person: person,
                          canRemove: me.canManageStaff && !person.isMe,
                          onRemove: () => _confirmRemove(person),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (me.canManageStaff) ...[
                  Text('Add someone',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Give them a code. They install ShopPadi, sign in, and '
                    'enter it — the shop appears on their phone.',
                    style: TextStyle(color: scheme.outline),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _invite(ShopRole.cashier),
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Invite a cashier'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _invite(ShopRole.manager),
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Invite a manager'),
                  ),
                  const SizedBox(height: 20),
                  _RoleKey(scheme: scheme),
                ] else
                  _Explain(
                    icon: Icons.lock_outline,
                    title: 'Only the owner can change the team',
                    body: 'You are signed in as ${me.label.toLowerCase()}.',
                    colour: scheme.outline,
                  ),
              ],
            ),
    );
  }

  Future<void> _invite(ShopRole role) async {
    setState(() => _busy = true);
    try {
      final code = await ref.read(authServiceProvider).createInvite(role: role);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => _InviteCodeDialog(code: code, role: role),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not make a code: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmRemove(StaffMember person) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${person.displayName}?'),
        content: const Text(
            'They lose access on their next sync. Sales they already recorded '
            'stay on the books with their name against them.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Keep them')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (yes != true) return;

    try {
      await ref.read(authServiceProvider).removeStaff(person.userId);
      ref.invalidate(staffProvider);
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not remove: $e')));
      }
    }
  }
}

class _InviteCodeDialog extends StatelessWidget {
  const _InviteCodeDialog({required this.code, required this.role});

  final String code;
  final ShopRole role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roleName = role == ShopRole.manager ? 'manager' : 'cashier';

    return AlertDialog(
      title: Text('Code for a $roleName'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              code,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                letterSpacing: 6,
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Good for 7 days, and works once. They enter it under '
            'More → Staff after signing in.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.outline, fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: code));
            Navigator.of(context).pop();
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () {
            Share.share('Join my shop on ShopPadi with this code: $code');
            Navigator.of(context).pop();
          },
          child: const Text('Send'),
        ),
      ],
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({
    required this.person,
    required this.canRemove,
    required this.onRemove,
  });

  final StaffMember person;
  final bool canRemove;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roleLabel = switch (person.role) {
      ShopRole.owner => 'Owner — sees everything',
      ShopRole.manager => person.canSeeProfit
          ? 'Manager — sees profit'
          : 'Manager — no profit figures',
      ShopRole.cashier => 'Cashier — sells only',
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor:
            person.role == ShopRole.owner ? scheme.primary : scheme.secondary,
        child: Text(
          person.displayName.characters.first.toUpperCase(),
          style: TextStyle(color: scheme.onPrimary),
        ),
      ),
      title: Text(person.isMe
          ? '${person.displayName} (you)'
          : person.displayName),
      subtitle: Text(roleLabel),
      trailing: canRemove
          ? IconButton(
              icon: const Icon(Icons.person_remove_outlined),
              tooltip: 'Remove',
              onPressed: onRemove,
            )
          : null,
    );
  }
}

class _RoleKey extends StatelessWidget {
  const _RoleKey({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What each one can do',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            'Cashier — rings up sales, takes payment, prints receipts. Cannot '
            'see what anything cost you or what you made on it.\n\n'
            'Manager — everything a cashier can, plus stock, prices, expenses '
            'and returns. Profit figures stay hidden unless you say otherwise.\n\n'
            'Owner — everything, including the team and the books.',
            style: TextStyle(color: scheme.outline, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Explain extends StatelessWidget {
  const _Explain({
    required this.icon,
    required this.title,
    required this.body,
    required this.colour,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: colour, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(color: colour, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
