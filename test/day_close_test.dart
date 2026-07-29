import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/channels.dart';
import 'package:shoppadi/core/db/day_close_repository.dart';

void main() {
  group('till status', () {
    test('exact match balances', () {
      expect(tillStatus(0), TillStatus.balanced);
    });

    test('missing money is short', () {
      expect(tillStatus(-50000), TillStatus.short);
    });

    test('extra money is over', () {
      expect(tillStatus(20000), TillStatus.over);
    });
  });

  group('day takings', () {
    const takings = DayTakings(
      cash: 1620000,
      channels: {'opay': 620000, 'moniepoint': 415000},
      saleCount: 37,
    );

    test('total spans cash and every channel', () {
      expect(takings.channelTotal, 1035000);
      expect(takings.total, 2655000);
    });

    test('allChannels puts cash alongside the wallets', () {
      expect(takings.allChannels,
          {'cash': 1620000, 'opay': 620000, 'moniepoint': 415000});
    });

    test('an empty day totals zero', () {
      expect(DayTakings.empty.total, 0);
      expect(DayTakings.empty.allChannels, {'cash': 0});
    });
  });

  group('stored channel totals', () {
    test('survive a round trip', () {
      const original = DayTakings(
        cash: 500000,
        channels: {'palmpay': 250000, 'pos': 75000},
        saleCount: 4,
      );
      final restored =
          decodeChannelTotals('{"cash":500000,"palmpay":250000,"pos":75000}');
      expect(restored, original.allChannels);
    });
  });

  group('channel labels', () {
    test('every transfer channel has a label', () {
      for (final key in transferChannels) {
        expect(channelLabels.containsKey(key), isTrue, reason: 'missing $key');
      }
    });

    test('unknown keys fall back to the raw value', () {
      expect(channelLabel('kuda'), 'kuda');
      expect(channelLabel('moniepoint'), 'Moniepoint');
    });
  });
}
