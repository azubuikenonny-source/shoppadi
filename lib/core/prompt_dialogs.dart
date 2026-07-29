import 'package:flutter/material.dart';

import 'money.dart';

/// Small prompts that own their text controllers.
///
/// Creating a controller beside `showDialog` and disposing it as soon as the
/// future completes crashes with `_dependents.isEmpty`: the dialog's exit
/// animation is still running, so the TextField is alive when the controller
/// dies. A StatefulWidget that disposes in its own `dispose` cannot get that
/// wrong.

Future<double?> askQuantity(
  BuildContext context, {
  required String title,
  double initial = 1,
}) async {
  final result = await showDialog<double>(
    context: context,
    builder: (_) => _QuantityPrompt(title: title, initial: initial),
  );
  return (result == null || result <= 0) ? null : result;
}

class _QuantityPrompt extends StatefulWidget {
  const _QuantityPrompt({required this.title, required this.initial});

  final String title;
  final double initial;

  @override
  State<_QuantityPrompt> createState() => _QuantityPromptState();
}

class _QuantityPromptState extends State<_QuantityPrompt> {
  late final TextEditingController _controller = TextEditingController(
      text: widget.initial == widget.initial.roundToDouble()
          ? widget.initial.round().toString()
          : widget.initial.toString());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop(double.tryParse(_controller.text.trim()));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(labelText: 'Quantity'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

/// Asks for a naira amount and returns it in kobo.
Future<int?> askAmount(
  BuildContext context, {
  required String title,
  required String label,
  String? helperText,
  int? initialKobo,
  String confirmLabel = 'Save',
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _AmountPrompt(
      title: title,
      label: label,
      helperText: helperText,
      initialKobo: initialKobo,
      confirmLabel: confirmLabel,
    ),
  );
}

class _AmountPrompt extends StatefulWidget {
  const _AmountPrompt({
    required this.title,
    required this.label,
    required this.confirmLabel,
    this.helperText,
    this.initialKobo,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String? helperText;
  final int? initialKobo;

  @override
  State<_AmountPrompt> createState() => _AmountPromptState();
}

class _AmountPromptState extends State<_AmountPrompt> {
  late final TextEditingController _controller = TextEditingController(
      text: widget.initialKobo == null
          ? ''
          : (widget.initialKobo! / 100).toStringAsFixed(2));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop(parseNairaToKobo(_controller.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.label,
          prefixText: '₦',
          helperText: widget.helperText,
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}

/// A hand-typed invoice line: something that is not stock.
typedef FreeLine = ({String description, double qty, int unitPrice});

Future<FreeLine?> askFreeLine(BuildContext context) {
  return showDialog<FreeLine>(
    context: context,
    builder: (_) => const _FreeLinePrompt(),
  );
}

class _FreeLinePrompt extends StatefulWidget {
  const _FreeLinePrompt();

  @override
  State<_FreeLinePrompt> createState() => _FreeLinePromptState();
}

class _FreeLinePromptState extends State<_FreeLinePrompt> {
  final _description = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();

  @override
  void dispose() {
    _description.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final description = _description.text.trim();
    final price = parseNairaToKobo(_price.text);
    final qty = double.tryParse(_qty.text.trim()) ?? 1;
    if (description.isEmpty || price == null || qty <= 0) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context)
        .pop((description: description, qty: qty, unitPrice: price));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Type a line'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _description,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
                labelText: 'Description', hintText: 'Delivery, labour…'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Qty'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _price,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                      labelText: 'Unit price', prefixText: '₦'),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Add')),
      ],
    );
  }
}

/// Name and phone for a customer created mid-checkout.
typedef NewCustomer = ({String name, String? phone});

Future<NewCustomer?> askNewCustomer(BuildContext context) {
  return showDialog<NewCustomer>(
    context: context,
    builder: (_) => const _NewCustomerPrompt(),
  );
}

class _NewCustomerPrompt extends StatefulWidget {
  const _NewCustomerPrompt();

  @override
  State<_NewCustomerPrompt> createState() => _NewCustomerPromptState();
}

class _NewCustomerPromptState extends State<_NewCustomerPrompt> {
  final _name = TextEditingController();
  final _phone = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final phone = _phone.text.trim();
    Navigator.of(context)
        .pop((name: name, phone: phone.isEmpty ? null : phone));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New customer'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            onSubmitted: (_) => _submit(),
            decoration: const InputDecoration(labelText: 'Phone (WhatsApp)'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
