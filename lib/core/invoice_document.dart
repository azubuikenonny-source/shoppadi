import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'channels.dart';
import 'db/invoices_repository.dart';
import 'db/settings_repository.dart';
import 'money.dart';

/// An invoice in the two forms a Nigerian shop actually sends: pasted into
/// WhatsApp, or attached as a document for a customer who needs one on file.
class InvoiceDocument {
  static final _date = DateFormat('d MMM yyyy');

  static String reference(int invoiceNo, DateTime issuedAt) =>
      'INV-${issuedAt.year}-${invoiceNo.toString().padLeft(4, '0')}';

  static String fileName(int invoiceNo, DateTime issuedAt) =>
      '${reference(invoiceNo, issuedAt)}.pdf';

  /// Plain text for WhatsApp — no attachment, no data cost, reads fine on any
  /// phone. The ₦ sign is safe here because the phone renders it, not a PDF.
  static String text({
    required ShopProfile shop,
    required int invoiceNo,
    required DateTime issuedAt,
    required String customerName,
    required List<InvoiceItem> items,
    required int subtotal,
    required int vatAmount,
    required int total,
    required int amountPaid,
    DateTime? dueDate,
    String? note,
  }) {
    final buffer = StringBuffer()
      ..writeln('*${shop.displayName.toUpperCase()}*');
    if (shop.phone.trim().isNotEmpty) buffer.writeln(shop.phone.trim());

    buffer
      ..writeln('')
      ..writeln('*INVOICE ${reference(invoiceNo, issuedAt)}*')
      ..writeln('Date: ${_date.format(issuedAt)}');
    if (dueDate != null) buffer.writeln('Due: ${_date.format(dueDate)}');
    buffer
      ..writeln('Bill to: $customerName')
      ..writeln('------------------------------');

    for (final item in items) {
      buffer
        ..writeln('${_qty(item.qty)} x ${item.description}')
        ..writeln('     ${formatKoboCompact(item.lineTotal)}');
    }

    buffer.writeln('------------------------------');
    if (vatAmount > 0) {
      buffer
        ..writeln('Subtotal: ${formatKoboCompact(subtotal)}')
        ..writeln('VAT: ${formatKoboCompact(vatAmount)}');
    }
    buffer.writeln('*TOTAL: ${formatKoboCompact(total)}*');

    final owing = total - amountPaid;
    if (amountPaid > 0) buffer.writeln('Paid: ${formatKoboCompact(amountPaid)}');
    if (owing > 0) {
      buffer.writeln('*AMOUNT DUE: ${formatKoboCompact(owing)}*');
    } else {
      buffer.writeln('*PAID IN FULL — thank you*');
    }

    if (shop.accounts.isNotEmpty && owing > 0) {
      buffer.writeln('');
      buffer.writeln('To pay, transfer to:');
      for (final entry in shop.accounts.entries) {
        buffer.writeln('${channelLabel(entry.key)}: ${entry.value}');
      }
    }

    if (note != null && note.trim().isNotEmpty) {
      buffer
        ..writeln('')
        ..writeln(note.trim());
    }

    return buffer.toString().trimRight();
  }

  /// A one-page A4 document. Money is written as "NGN 1,500.00" because the
  /// ₦ glyph does not exist in the standard PDF fonts and would print blank.
  static Future<Uint8List> pdf({
    required ShopProfile shop,
    required int invoiceNo,
    required DateTime issuedAt,
    required String customerName,
    String? customerPhone,
    required List<InvoiceItem> items,
    required int subtotal,
    required int vatAmount,
    required int total,
    required int amountPaid,
    DateTime? dueDate,
    String? note,
  }) async {
    final doc = pw.Document();
    final owing = total - amountPaid;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(shop.displayName.toUpperCase(),
                        style: pw.TextStyle(
                            fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    if (shop.phone.trim().isNotEmpty)
                      pw.Text(shop.phone.trim(),
                          style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('INVOICE',
                        style: pw.TextStyle(
                            fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text(reference(invoiceNo, issuedAt),
                        style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Divider(thickness: 1.2),
            pw.SizedBox(height: 10),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('BILL TO',
                        style: pw.TextStyle(
                            fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    pw.Text(customerName),
                    if (customerPhone != null && customerPhone.trim().isNotEmpty)
                      pw.Text(customerPhone.trim(),
                          style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Date: ${_date.format(issuedAt)}',
                        style: const pw.TextStyle(fontSize: 10)),
                    if (dueDate != null)
                      pw.Text('Due: ${_date.format(dueDate)}',
                          style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.TableHelper.fromTextArray(
              headerStyle: pw.TextStyle(
                  fontSize: 9, fontWeight: pw.FontWeight.bold),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding:
                  const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              headerAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerRight,
                2: pw.Alignment.centerRight,
                3: pw.Alignment.centerRight,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(4),
                1: const pw.FlexColumnWidth(1),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              headers: ['Description', 'Qty', 'Unit price', 'Amount'],
              data: [
                for (final item in items)
                  [
                    item.description,
                    _qty(item.qty),
                    formatKoboAsCode(item.unitPrice),
                    formatKoboAsCode(item.lineTotal),
                  ],
              ],
            ),
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.SizedBox(
                width: 240,
                child: pw.Column(
                  children: [
                    if (vatAmount > 0) ...[
                      _pdfRow('Subtotal', formatKoboAsCode(subtotal)),
                      _pdfRow('VAT', formatKoboAsCode(vatAmount)),
                    ],
                    pw.Divider(),
                    _pdfRow('Total', formatKoboAsCode(total), bold: true),
                    if (amountPaid > 0)
                      _pdfRow('Paid', formatKoboAsCode(amountPaid)),
                    _pdfRow(owing > 0 ? 'Amount due' : 'Paid in full',
                        owing > 0 ? formatKoboAsCode(owing) : '',
                        bold: true),
                  ],
                ),
              ),
            ),
            if (shop.accounts.isNotEmpty && owing > 0) ...[
              pw.SizedBox(height: 20),
              pw.Text('PAYMENT DETAILS',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              for (final entry in shop.accounts.entries)
                pw.Text('${channelLabel(entry.key)}: ${entry.value}',
                    style: const pw.TextStyle(fontSize: 10)),
            ],
            if (note != null && note.trim().isNotEmpty) ...[
              pw.SizedBox(height: 18),
              pw.Text(note.trim(), style: const pw.TextStyle(fontSize: 10)),
            ],
            pw.Spacer(),
            pw.Center(
              child: pw.Text(shop.receiptFooter.trim(),
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            ),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _pdfRow(String label, String value, {bool bold = false}) {
    final style = pw.TextStyle(
        fontSize: 11,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [pw.Text(label, style: style), pw.Text(value, style: style)],
      ),
    );
  }

  static String _qty(double q) =>
      q == q.roundToDouble() ? q.round().toString() : q.toString();
}
