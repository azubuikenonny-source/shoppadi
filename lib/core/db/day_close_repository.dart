import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'outbox.dart';

const _uuid = Uuid();

/// What the shop took in on a given day, split by where the money landed.
/// Cash is separated because it is the only channel that can physically walk
/// off — the others are checked against each wallet app.
class DayTakings {
  const DayTakings({
    required this.cash,
    required this.channels,
    required this.saleCount,
  });

  final int cash; // kobo
  final Map<String, int> channels; // opay/palmpay/moniepoint/bank/pos/card
  final int saleCount;

  static const empty = DayTakings(cash: 0, channels: {}, saleCount: 0);

  int get channelTotal =>
      channels.values.fold<int>(0, (sum, amount) => sum + amount);

  int get total => cash + channelTotal;

  Map<String, int> get allChannels => {'cash': cash, ...channels};
}

enum TillStatus { balanced, short, over }

/// counted − expected. Negative means money is missing.
TillStatus tillStatus(int difference) => switch (difference) {
      0 => TillStatus.balanced,
      < 0 => TillStatus.short,
      _ => TillStatus.over,
    };

class DayCloseRepository {
  DayCloseRepository(this.db);

  final AppDatabase db;

  static DateTime dayOf(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Live takings for [date]. Watches sales because every sale and every
  /// repayment touches that table, so the figures never go stale mid-shift.
  Stream<DayTakings> watchTakings(DateTime date) =>
      db.select(db.sales).watch().asyncMap((_) => takingsFor(date));

  Future<DayTakings> takingsFor(DateTime date) async {
    final start = dayOf(date);
    final end = start.add(const Duration(days: 1));

    final payments = await (db.select(db.payments)
          ..where((p) =>
              p.createdAt.isBiggerOrEqualValue(start) &
              p.createdAt.isSmallerThanValue(end)))
        .get();

    final sales = await (db.select(db.sales)
          ..where((s) =>
              s.saleDate.isBiggerOrEqualValue(start) &
              s.saleDate.isSmallerThanValue(end)))
        .get();

    var cash = 0;
    final channels = <String, int>{};
    for (final payment in payments) {
      switch (payment.method) {
        case 'cash':
          cash += payment.amount;
        case 'transfer':
          final key = payment.channel ?? 'bank';
          channels[key] = (channels[key] ?? 0) + payment.amount;
        default: // pos, card
          channels[payment.method] =
              (channels[payment.method] ?? 0) + payment.amount;
      }
    }

    return DayTakings(
      cash: cash,
      channels: channels,
      saleCount: sales.length,
    );
  }

  /// The close for [date], or null if the till is still open. Ordered and
  /// limited so a duplicate row could never make this throw mid-shift.
  Stream<DayClose?> watchClose(DateTime date) {
    final day = dayOf(date);
    return (db.select(db.dayCloses)
          ..where((c) => c.closeDate.equals(day))
          ..orderBy([
            (c) => OrderingTerm(
                expression: c.createdAt, mode: OrderingMode.desc)
          ])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<DayClose?> closeFor(DateTime date) =>
      (db.select(db.dayCloses)..where((c) => c.closeDate.equals(dayOf(date))))
          .getSingleOrNull();

  Stream<List<DayClose>> watchHistory({int limit = 30}) =>
      (db.select(db.dayCloses)
            ..orderBy([
              (c) => OrderingTerm(
                  expression: c.closeDate, mode: OrderingMode.desc)
            ])
            ..limit(limit))
          .watch();

  /// Records the close. A day can only be closed once — a second attempt is
  /// ignored rather than overwriting the first count.
  Future<void> close({
    required DateTime date,
    required int countedCash,
    required DayTakings takings,
    String? note,
  }) async {
    if (await closeFor(date) != null) return;

    final id = _uuid.v4();
    await db.into(db.dayCloses).insert(DayClosesCompanion.insert(
          id: id,
          closeDate: dayOf(date),
          expectedCash: takings.cash,
          countedCash: countedCash,
          channelTotals: jsonEncode(takings.allChannels),
          note: Value(note == null || note.trim().isEmpty ? null : note.trim()),
          createdAt: DateTime.now(),
        ));
    await enqueue(db, 'day_closes', id);
  }
}

/// Reads back the per-channel figures stored with a close.
Map<String, int> decodeChannelTotals(String json) {
  final decoded = jsonDecode(json) as Map<String, dynamic>;
  return decoded.map((key, value) => MapEntry(key, (value as num).toInt()));
}
