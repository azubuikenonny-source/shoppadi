import 'package:intl/intl.dart';

import 'db/settings_repository.dart';
import 'money.dart';

class ReceiptLine {
  const ReceiptLine({
    required this.name,
    required this.qty,
    required this.lineTotal,
  });

  final String name;
  final double qty;
  final int lineTotal; // kobo
}

/// The digital receipt (design doc 4.4). Plain text on purpose: it pastes into
/// WhatsApp intact on any phone, needs no PDF viewer, and costs nothing to send.
class Receipt {
  static final _date = DateFormat('d MMM yyyy, h:mm a');

  static const _channelNames = {
    'opay': 'OPay',
    'palmpay': 'PalmPay',
    'moniepoint': 'Moniepoint',
    'bank': 'Bank',
  };

  static String build({
    required ShopProfile shop,
    required int receiptNo,
    required List<ReceiptLine> lines,
    required int total,
    required int amountPaid,
    int discount = 0,
    DateTime? at,
    String? customerName,
  }) {
    final balance = total - amountPaid;
    final buffer = StringBuffer()
      ..writeln('*${shop.displayName.toUpperCase()}*');

    if (shop.phone.trim().isNotEmpty) buffer.writeln(shop.phone.trim());
    buffer
      ..writeln('Receipt #$receiptNo')
      ..writeln(_date.format(at ?? DateTime.now()));
    if (customerName != null) buffer.writeln('Customer: $customerName');
    buffer.writeln('------------------------------');

    for (final line in lines) {
      final qty = line.qty == line.qty.roundToDouble()
          ? line.qty.round().toString()
          : line.qty.toString();
      buffer.writeln('$qty x ${line.name}');
      buffer.writeln('     ${formatKoboCompact(line.lineTotal)}');
    }

    buffer.writeln('------------------------------');
    // The discount goes on paper: a customer given something off wants to see
    // it, and a shop owner reviewing receipts wants to see who gave it.
    if (discount > 0) {
      buffer.writeln('Discount: -${formatKoboCompact(discount)}');
    }
    buffer
      ..writeln('*TOTAL: ${formatKoboCompact(total)}*')
      ..writeln('Paid: ${formatKoboCompact(amountPaid)}');

    if (balance > 0) {
      buffer.writeln('*BALANCE DUE: ${formatKoboCompact(balance)}*');
    }

    if (shop.accounts.isNotEmpty && balance > 0) {
      buffer.writeln('');
      buffer.writeln('To pay, transfer to:');
      for (final entry in shop.accounts.entries) {
        final label = _channelNames[entry.key] ?? entry.key;
        buffer.writeln('$label: ${entry.value}');
      }
    }

    if (shop.receiptFooter.trim().isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln(shop.receiptFooter.trim());
    }

    return buffer.toString().trimRight();
  }
}
