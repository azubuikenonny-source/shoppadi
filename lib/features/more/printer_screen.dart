import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/settings_repository.dart';
import '../../core/printing/printer_service.dart';
import '../../core/printing/thermal_receipt.dart';
import '../../core/providers.dart';
import '../../core/receipt.dart';

/// Pair a receipt printer and prove it works before a customer is waiting
/// (design doc 4.4).
class PrinterScreen extends ConsumerStatefulWidget {
  const PrinterScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => const PrinterScreen()));

  @override
  ConsumerState<PrinterScreen> createState() => _PrinterScreenState();
}

class _PrinterScreenState extends ConsumerState<PrinterScreen> {
  List<PairedPrinter>? _printers;
  bool _bluetoothOn = true;
  bool _loading = true;
  bool _busy = false;

  String? _mac;
  String? _name;
  int _width = PaperWidth.mm58;
  bool _autoPrint = false;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final service = ref.read(printerServiceProvider);
    final on = await service.bluetoothOn;
    final list = on ? await service.paired() : <PairedPrinter>[];
    if (!mounted) return;
    setState(() {
      _bluetoothOn = on;
      _printers = list;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await ref.read(settingsRepoProvider).savePrinter(
          mac: _mac,
          name: _name,
          paperWidth: _width,
          autoPrint: _autoPrint,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Printer settings saved')));
  }

  Future<void> _testPrint() async {
    setState(() => _busy = true);
    final shop = ref.read(shopProfileProvider).valueOrNull ?? const ShopProfile();

    final outcome = await ref.read(printerServiceProvider).send(
          ThermalReceipt.bytes(
            shop: shop,
            receiptNo: 0,
            items: const [
              ReceiptLine(name: 'Test print', qty: 1, lineTotal: 100000),
            ],
            total: 100000,
            amountPaid: 100000,
            width: _width,
          ),
          mac: _mac,
        );

    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(printOutcomeMessage(outcome))));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(shopProfileProvider);
    final shop = profile.valueOrNull ?? const ShopProfile();
    final scheme = Theme.of(context).colorScheme;

    if (profile.hasValue && !_seeded) {
      _seeded = true;
      _mac = shop.printerMac?.isEmpty ?? true ? null : shop.printerMac;
      _name = shop.printerName;
      _width = shop.paperWidth;
      _autoPrint = shop.autoPrint;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receipt printer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Look again',
            onPressed: _loading ? null : _refresh,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const Center(child: Padding(
                padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
          else if (!_bluetoothOn)
            _Notice(
              icon: Icons.bluetooth_disabled,
              title: 'Bluetooth is off',
              body: 'Turn it on, then tap refresh.',
              color: scheme.error,
            )
          else if ((_printers ?? const []).isEmpty)
            _Notice(
              icon: Icons.print_disabled_outlined,
              title: 'No paired printers',
              body: 'Pair the printer in Android Settings → Bluetooth first, '
                  'then come back and tap refresh.',
              color: scheme.tertiary,
            )
          else ...[
            Text('Paired printers',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: _mac,
              onChanged: (value) => setState(() {
                _mac = value;
                _name = _printers
                    ?.where((printer) => printer.mac == value)
                    .firstOrNull
                    ?.name;
              }),
              child: Column(
                children: [
                  for (final printer in _printers!)
                    RadioListTile<String>(
                      contentPadding: EdgeInsets.zero,
                      value: printer.mac,
                      title: Text(printer.name),
                      subtitle: Text(printer.mac),
                    ),
                ],
              ),
            ),
          ],
          const Divider(height: 28),
          Text('Paper width', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final width in PaperWidth.all)
                ButtonSegment(
                    value: width, label: Text(PaperWidth.label(width))),
            ],
            selected: {_width},
            onSelectionChanged: (s) => setState(() => _width = s.first),
          ),
          const SizedBox(height: 8),
          Text('58mm is the small handheld printer; 80mm is the wider desk one.',
              style: TextStyle(color: scheme.outline, fontSize: 12)),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _autoPrint,
            onChanged: (v) => setState(() => _autoPrint = v),
            title: const Text('Print after every sale'),
            subtitle: const Text('No extra tap at the counter'),
          ),
          const SizedBox(height: 12),
          Text('This is what prints',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Preview(shop: shop, width: _width),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: (_busy || _mac == null) ? null : _testPrint,
            icon: const Icon(Icons.print_outlined),
            label: const Text('Test print'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Renders the receipt in a monospace block at the real paper width, so the
/// owner can see the wrapping before wasting a roll on it.
class _Preview extends StatelessWidget {
  const _Preview({required this.shop, required this.width});

  final ShopProfile shop;
  final int width;

  @override
  Widget build(BuildContext context) {
    final lines = ThermalReceipt.layout(
      shop: shop,
      receiptNo: 41,
      items: const [
        ReceiptLine(name: 'Peak Milk sachet', qty: 2, lineTotal: 80000),
        ReceiptLine(name: 'Golden Penny Semovita 1kg', qty: 1, lineTotal: 220000),
      ],
      total: 300000,
      amountPaid: 200000,
      at: DateTime(2026, 7, 25, 10, 47),
      width: width,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text(
          lines.join('\n'),
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 11, height: 1.35),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600)),
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
