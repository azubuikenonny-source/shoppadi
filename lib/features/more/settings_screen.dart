import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Shop details that appear on every receipt and WhatsApp message.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  static const _channels = {
    'opay': 'OPay',
    'palmpay': 'PalmPay',
    'moniepoint': 'Moniepoint',
    'bank': 'Bank account',
  };

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _footer = TextEditingController();
  final _accounts = {for (final k in _channels.keys) k: TextEditingController()};
  final _vatRate = TextEditingController();
  bool _vatEnabled = false;
  bool _loaded = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _footer.dispose();
    _vatRate.dispose();
    for (final c in _accounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    await ref.read(settingsRepoProvider).saveProfile(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          receiptFooter: _footer.text.trim(),
          accounts: {
            for (final entry in _accounts.entries)
              entry.key: entry.value.text.trim(),
          },
        );
    await ref.read(settingsRepoProvider).saveVat(
          enabled: _vatEnabled,
          rate: double.tryParse(_vatRate.text.trim()) ?? 7.5,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Shop details saved')));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(shopProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shop details')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load settings: $e')),
        data: (p) {
          // Seed the fields once; later stream events must not fight typing.
          if (!_loaded) {
            _loaded = true;
            _name.text = p.name;
            _phone.text = p.phone;
            _footer.text = p.receiptFooter;
            for (final entry in _accounts.entries) {
              entry.value.text = p.accounts[entry.key] ?? '';
            }
            _vatEnabled = p.vatEnabled;
            _vatRate.text = p.vatRate.toString();
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Shop name',
                  helperText: 'Prints at the top of every receipt',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Shop phone'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _footer,
                decoration: const InputDecoration(
                  labelText: 'Receipt footer',
                  helperText: 'e.g. No refund after 7 days',
                ),
              ),
              const SizedBox(height: 24),
              Text('Accounts customers pay into',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'These print on receipts when money is still owed.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
              const SizedBox(height: 12),
              for (final entry in _channels.entries) ...[
                TextField(
                  controller: _accounts[entry.key],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: entry.value,
                    hintText: 'Account number',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 12),
              Text('Tax', style: Theme.of(context).textTheme.titleMedium),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _vatEnabled,
                onChanged: (v) => setState(() => _vatEnabled = v),
                title: const Text('Charge VAT on invoices'),
                subtitle: Text(_vatEnabled
                    ? 'Added on top of the invoice subtotal'
                    : 'Leave off if you are below the VAT threshold'),
              ),
              if (_vatEnabled)
                TextField(
                  controller: _vatRate,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'VAT rate',
                    suffixText: '%',
                    helperText: 'Estimate only — not tax advice',
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _save,
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
