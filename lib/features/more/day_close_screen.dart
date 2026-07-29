import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/channels.dart';
import '../../core/db/database.dart';
import '../../core/db/day_close_repository.dart';
import '../../core/money.dart';
import '../../core/providers.dart';

/// Count the till, balance every channel (design doc 4.12). The one screen
/// that answers "is the money that should be here, here?"
class DayCloseScreen extends ConsumerWidget {
  const DayCloseScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DayCloseScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final takings = ref.watch(todayTakingsProvider);
    final close = ref.watch(todayCloseProvider);
    final history = ref.watch(closeHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Close day')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(DateFormat('EEEE, d MMMM').format(DateTime.now()),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          switch ((takings, close)) {
            (AsyncData(value: final t), AsyncData(value: final c)) => c == null
                ? _CloseForm(takings: t)
                : _ClosedCard(close: c),
            (AsyncError(error: final e), _) ||
            (_, AsyncError(error: final e)) =>
              Text('Could not load the day: $e'),
            _ => const Center(child: CircularProgressIndicator()),
          },
          const SizedBox(height: 28),
          Text('Past closes', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          history.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Could not load history: $e'),
            data: (list) {
              final past = list
                  .where((c) =>
                      c.closeDate != DayCloseRepository.dayOf(DateTime.now()))
                  .toList();
              if (past.isEmpty) {
                return Text('Nothing closed yet.',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline));
              }
              return Column(
                children: [for (final c in past) _HistoryTile(close: c)],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CloseForm extends ConsumerStatefulWidget {
  const _CloseForm({required this.takings});

  final DayTakings takings;

  @override
  ConsumerState<_CloseForm> createState() => _CloseFormState();
}

class _CloseFormState extends ConsumerState<_CloseForm> {
  final _counted = TextEditingController();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _counted.dispose();
    _note.dispose();
    super.dispose();
  }

  int? get _countedKobo => parseNairaToKobo(_counted.text);
  int? get _difference => _countedKobo == null
      ? null
      : _countedKobo! - widget.takings.cash;

  Future<void> _close() async {
    final counted = _countedKobo;
    if (counted == null) return;
    setState(() => _saving = true);

    await ref.read(dayCloseRepoProvider).close(
          date: DateTime.now(),
          countedCash: counted,
          takings: widget.takings,
          note: _note.text,
        );

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Day closed. Records are locked.')));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = widget.takings;
    final difference = _difference;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Took in today',
                    style: TextStyle(color: scheme.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text(formatKoboCompact(t.total),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold)),
                Text('${t.saleCount} sale${t.saleCount == 1 ? '' : 's'}',
                    style: TextStyle(color: scheme.onPrimaryContainer)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Check each channel',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 4),
        Text('Open each app and confirm the figures match.',
            style: TextStyle(color: scheme.outline, fontSize: 12)),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              for (final entry in t.allChannels.entries)
                if (entry.value != 0 || entry.key == 'cash')
                  ListTile(
                    dense: true,
                    title: Text(channelLabel(entry.key)),
                    trailing: Text(formatKoboCompact(entry.value),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Now count the cash in the till',
            style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        TextField(
          controller: _counted,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Cash counted',
            prefixText: '₦',
            helperText: 'Expected ${formatKoboCompact(t.cash)}',
          ),
        ),
        if (difference != null) ...[
          const SizedBox(height: 12),
          _DifferenceBanner(difference: difference),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: 'Note',
            hintText: difference != null && difference != 0
                ? 'What happened?'
                : 'Anything worth remembering',
            helperText: 'Saved permanently with this close',
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: (_saving || _countedKobo == null) ? null : _close,
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16)),
          child: Text(_countedKobo == null ? 'Enter the cash count' : 'Close day'),
        ),
      ],
    );
  }
}

class _DifferenceBanner extends StatelessWidget {
  const _DifferenceBanner({required this.difference});

  final int difference;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = tillStatus(difference);
    final (color, icon, text) = switch (status) {
      TillStatus.balanced => (
          scheme.primary,
          Icons.check_circle_outline,
          'Balanced — the till matches exactly'
        ),
      TillStatus.short => (
          scheme.error,
          Icons.error_outline,
          'Short ${formatKoboCompact(difference.abs())}'
        ),
      TillStatus.over => (
          scheme.tertiary,
          Icons.info_outline,
          'Over ${formatKoboCompact(difference)}'
        ),
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ClosedCard extends StatelessWidget {
  const _ClosedCard({required this.close});

  final DayClose close;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final difference = close.countedCash - close.expectedCash;
    final totals = decodeChannelTotals(close.channelTotals);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 18, color: scheme.outline),
                    const SizedBox(width: 6),
                    Text('Closed at ${DateFormat.Hm().format(close.createdAt)}',
                        style: TextStyle(color: scheme.outline)),
                  ],
                ),
                const SizedBox(height: 12),
                _Row(label: 'Cash expected', value: close.expectedCash),
                _Row(label: 'Cash counted', value: close.countedCash),
                const Divider(),
                for (final entry in totals.entries)
                  if (entry.key != 'cash' && entry.value != 0)
                    _Row(label: channelLabel(entry.key), value: entry.value),
                const SizedBox(height: 8),
                _DifferenceBanner(difference: difference),
                if (close.note != null) ...[
                  const SizedBox(height: 12),
                  Text(close.note!, style: TextStyle(color: scheme.outline)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(formatKoboCompact(value),
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.close});

  final DayClose close;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final difference = close.countedCash - close.expectedCash;
    final status = tillStatus(difference);
    final (color, label) = switch (status) {
      TillStatus.balanced => (scheme.primary, 'Balanced'),
      TillStatus.short => (scheme.error, 'Short ${formatKoboCompact(difference.abs())}'),
      TillStatus.over => (scheme.tertiary, 'Over ${formatKoboCompact(difference)}'),
    };

    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(DateFormat('EEE d MMM').format(close.closeDate)),
      subtitle: close.note == null ? null : Text(close.note!),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(formatKoboCompact(close.countedCash),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
