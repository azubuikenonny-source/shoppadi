import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/db/database.dart';
import '../../core/db/invoices_repository.dart';
import '../../core/db/settings_repository.dart';
import '../../core/money.dart';
import '../../core/prompt_dialogs.dart';
import '../../core/providers.dart';

/// Compose or edit an invoice: pick products from the catalogue, or type a line
/// for anything that is not stock (delivery, labour, a bulk quote).
class InvoiceFormScreen extends ConsumerStatefulWidget {
  const InvoiceFormScreen({super.key, this.existing});

  final Invoice? existing;

  static Future<void> open(BuildContext context, {Invoice? existing}) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => InvoiceFormScreen(existing: existing)));

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _items = <InvoiceItem>[];
  String? _customerId;
  DateTime? _dueDate;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _name.text = existing.customerName;
      _phone.text = existing.customerPhone ?? '';
      _note.text = existing.note ?? '';
      _customerId = existing.customerId;
      _dueDate = existing.dueDate;
      _items.addAll(InvoiceItem.decodeAll(existing.items));
    } else {
      _dueDate = DateTime.now().add(const Duration(days: 7));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final shop = ref.read(shopProfileProvider).valueOrNull ?? const ShopProfile();
    if (_name.text.trim().isEmpty || _items.isEmpty) return;
    setState(() => _saving = true);

    final repo = ref.read(invoicesRepoProvider);
    if (_isEdit) {
      await repo.update(
        id: widget.existing!.id,
        customerName: _name.text.trim(),
        customerPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        items: _items,
        vatEnabled: shop.vatEnabled,
        vatRate: shop.vatRate,
        dueDate: _dueDate,
        note: _note.text,
      );
    } else {
      await repo.create(
        customerName: _name.text.trim(),
        customerId: _customerId,
        customerPhone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        items: _items,
        vatEnabled: shop.vatEnabled,
        vatRate: shop.vatRate,
        dueDate: _dueDate,
        note: _note.text,
      );
    }

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final shop = ref.watch(shopProfileProvider).valueOrNull ?? const ShopProfile();
    final totals = InvoiceTotals.of(_items,
        vatEnabled: shop.vatEnabled, vatRate: shop.vatRate);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit invoice' : 'New invoice')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Bill to'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.contacts_outlined),
                tooltip: 'Pick a saved customer',
                onPressed: _pickCustomer,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone (optional)'),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_dueDate == null
                ? 'No due date'
                : 'Due ${DateFormat('d MMMM yyyy').format(_dueDate!)}'),
            trailing: const Icon(Icons.edit_outlined, size: 18),
            onTap: _pickDueDate,
          ),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items', style: Theme.of(context).textTheme.titleMedium),
              Text('${_items.length}', style: TextStyle(color: scheme.outline)),
            ],
          ),
          const SizedBox(height: 4),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Add what you are billing for.',
                  style: TextStyle(color: scheme.outline)),
            ),
          for (var i = 0; i < _items.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_items[i].description),
              subtitle: Text(
                  '${_fmtQty(_items[i].qty)} × ${formatKoboCompact(_items[i].unitPrice)}'
                  '${_items[i].productId == null ? ' · typed in' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(formatKoboCompact(_items[i].lineTotal),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _items.removeAt(i)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addProduct,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('From stock'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _addFreeLine,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Type a line'),
                ),
              ),
            ],
          ),
          const Divider(height: 28),
          if (totals.vatAmount > 0) ...[
            _TotalRow(label: 'Subtotal', value: totals.subtotal),
            _TotalRow(
                label: 'VAT ${shop.vatRate.toStringAsFixed(1)}%',
                value: totals.vatAmount),
          ],
          _TotalRow(label: 'Total', value: totals.total, bold: true),
          if (!shop.vatEnabled)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('VAT is off — turn it on in Shop details if you charge it.',
                  style: TextStyle(color: scheme.outline, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Note on the invoice',
              hintText: 'Payment terms, delivery details…',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: (_saving || _items.isEmpty || _name.text.trim().isEmpty)
                ? null
                : _save,
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: Text(_isEdit ? 'Save changes' : 'Create invoice'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickCustomer() async {
    final customers = ref.read(customersProvider).valueOrNull ?? const [];
    if (customers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No saved customers yet — type the name instead.')));
      return;
    }

    final chosen = await showModalBottomSheet<Customer>(
      context: context,
      builder: (_) => ListView(
        children: [
          for (final customer in customers)
            ListTile(
              title: Text(customer.name),
              subtitle: customer.phone == null ? null : Text(customer.phone!),
              onTap: () => Navigator.of(context).pop(customer),
            ),
        ],
      ),
    );

    if (chosen != null) {
      setState(() {
        _customerId = chosen.id;
        _name.text = chosen.name;
        if (chosen.phone != null) _phone.text = chosen.phone!;
      });
    }
  }

  Future<void> _addProduct() async {
    final products = ref.read(activeProductsProvider).valueOrNull ?? const [];
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No products yet — add some in Inventory.')));
      return;
    }

    final chosen = await showModalBottomSheet<Product>(
      context: context,
      builder: (_) => ListView(
        children: [
          for (final product in products)
            ListTile(
              title: Text(product.name),
              trailing: Text(formatKoboCompact(product.sellingPrice)),
              onTap: () => Navigator.of(context).pop(product),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;

    final qty = await askQuantity(context, title: chosen.name);
    if (qty == null) return;

    setState(() => _items.add(InvoiceItem(
          description: chosen.name,
          qty: qty,
          unitPrice: chosen.sellingPrice,
          productId: chosen.id,
          costPerUnit: chosen.costPrice,
        )));
  }

  Future<void> _addFreeLine() async {
    final line = await askFreeLine(context);
    if (line == null) return;

    setState(() => _items.add(InvoiceItem(
          description: line.description,
          qty: line.qty,
          unitPrice: line.unitPrice,
        )));
  }

  static String _fmtQty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});

  final String label;
  final int value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
        fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        fontSize: bold ? 18 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(formatKoboCompact(value), style: style),
        ],
      ),
    );
  }
}
