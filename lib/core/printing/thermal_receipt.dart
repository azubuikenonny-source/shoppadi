import 'package:intl/intl.dart';

import '../channels.dart';
import '../db/settings_repository.dart';
import '../money.dart';
import '../receipt.dart';
import 'escpos.dart';

/// Characters per line. Cheap 58 mm printers fit 32, the 80 mm desk units 48 —
/// getting this wrong is what makes receipts wrap into unreadable stripes.
class PaperWidth {
  static const mm58 = 32;
  static const mm80 = 48;
  static const all = [mm58, mm80];

  static String label(int width) => width == mm80 ? '80mm' : '58mm';
}

/// Lays a receipt out as fixed-width text, then turns it into ESC/POS bytes.
/// The layout half is pure so it can be tested without a printer.
class ThermalReceipt {
  static final _stamp = DateFormat('d MMM yyyy, h:mm a');

  /// A label on the left and an amount on the right, filling [width].
  /// The label is truncated rather than allowed to push the amount off paper.
  static String row(String left, String right, int width) {
    if (right.length >= width) return right.substring(0, width);
    final room = width - right.length;
    final label = left.length > room - 1
        ? '${left.substring(0, (room - 2).clamp(0, room))} '
        : left;
    return label.padRight(room) + right;
  }

  static String centre(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    final pad = (width - text.length) ~/ 2;
    return ' ' * pad + text;
  }

  static String rule(int width, {String char = '-'}) => char * width;

  /// The receipt as plain lines — what the printer will actually put on paper.
  static List<String> layout({
    required ShopProfile shop,
    required int receiptNo,
    required List<ReceiptLine> items,
    required int total,
    required int amountPaid,
    int vatAmount = 0,
    DateTime? at,
    String? customerName,
    int width = PaperWidth.mm58,
  }) {
    final lines = <String>[];
    final balance = total - amountPaid;

    lines
      ..add(centre(shop.displayName.toUpperCase(), width))
      ..addIf(shop.phone.trim().isNotEmpty, centre(shop.phone.trim(), width))
      ..add(centre(_stamp.format(at ?? DateTime.now()), width))
      ..add(centre('Receipt #$receiptNo', width));
    if (customerName != null) {
      lines.add(centre(customerName, width));
    }
    lines.add(rule(width, char: '='));

    for (final item in items) {
      final qty = item.qty == item.qty.roundToDouble()
          ? item.qty.round().toString()
          : item.qty.toString();
      final label = '$qty x ${item.name}';
      final amount = formatKoboPlain(item.lineTotal);

      // Keep it on one line when it fits; otherwise the name gets its own line
      // so it is never chopped in half.
      if (label.length + amount.length + 1 <= width) {
        lines.add(row(label, amount, width));
      } else {
        lines
          ..add(label.length > width ? label.substring(0, width) : label)
          ..add(amount.padLeft(width));
      }
    }

    lines.add(rule(width, char: '='));
    if (vatAmount > 0) {
      lines.add(row('VAT included', formatKoboPlain(vatAmount), width));
    }
    lines.add(row('TOTAL', 'NGN ${formatKoboPlain(total)}', width));
    lines.add(row('Paid', formatKoboPlain(amountPaid), width));
    if (balance > 0) {
      lines
        ..add(row('BALANCE DUE', formatKoboPlain(balance), width))
        ..add(rule(width));
      if (shop.accounts.isNotEmpty) {
        lines.add('Transfer to:');
        for (final entry in shop.accounts.entries) {
          lines.add('${channelLabel(entry.key)}: ${entry.value}');
        }
      }
    }

    if (shop.receiptFooter.trim().isNotEmpty) {
      lines
        ..add(rule(width, char: '='))
        ..addAll(_wrap(shop.receiptFooter.trim(), width)
            .map((line) => centre(line, width)));
    }

    return lines;
  }

  /// Bytes for the printer. Emphasis is applied around the total, which is the
  /// one number a customer checks at a glance.
  static List<int> bytes({
    required ShopProfile shop,
    required int receiptNo,
    required List<ReceiptLine> items,
    required int total,
    required int amountPaid,
    int vatAmount = 0,
    DateTime? at,
    String? customerName,
    int width = PaperWidth.mm58,
  }) {
    final pos = EscPos()..init();
    final lines = layout(
      shop: shop,
      receiptNo: receiptNo,
      items: items,
      total: total,
      amountPaid: amountPaid,
      vatAmount: vatAmount,
      at: at,
      customerName: customerName,
      width: width,
    );

    for (final line in lines) {
      final isTotal = line.startsWith('TOTAL');
      final isBalance = line.startsWith('BALANCE DUE');
      if (isTotal || isBalance) pos.bold(true);
      pos.line(line);
      if (isTotal || isBalance) pos.bold(false);
    }

    return (pos
          ..feed(3)
          ..cut())
        .build();
  }

  static List<String> _wrap(String text, int width) {
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';
    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if (current.length + 1 + word.length <= width) {
        current = '$current $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }
}

extension _AddIf on List<String> {
  void addIf(bool condition, String value) {
    if (condition) add(value);
  }
}
