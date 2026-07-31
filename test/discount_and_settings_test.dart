import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/settings_repository.dart';
import 'package:shoppadi/core/printing/thermal_receipt.dart';
import 'package:shoppadi/core/receipt.dart';

const _shop = ShopProfile(name: "Nonny's Store", accounts: {});

const _lines = [
  ReceiptLine(name: 'Rice 5kg', qty: 1, lineTotal: 1050000),
  ReceiptLine(name: 'Sugar 1kg', qty: 2, lineTotal: 380000),
];

void main() {
  group('discount on the text receipt', () {
    test('appears when one was given', () {
      final text = Receipt.build(
        shop: _shop,
        receiptNo: 7,
        lines: _lines,
        total: 1380000, // 14,300 gross less 500 off
        amountPaid: 1380000,
        discount: 50000,
      );
      expect(text, contains('Discount: -₦500'));
      expect(text, contains('TOTAL: ₦13,800'));
    });

    test('absent when none was — a receipt should not advertise ₦0 off', () {
      final text = Receipt.build(
        shop: _shop,
        receiptNo: 8,
        lines: _lines,
        total: 1430000,
        amountPaid: 1430000,
      );
      expect(text, isNot(contains('Discount')));
    });
  });

  group('discount on thermal paper', () {
    test('prints its own row, inside the paper width', () {
      final lines = ThermalReceipt.layout(
        shop: _shop,
        receiptNo: 7,
        items: _lines,
        total: 1380000,
        amountPaid: 1380000,
        discount: 50000,
        at: DateTime(2026, 7, 31, 12),
      );
      final discountRow =
          lines.where((l) => l.startsWith('Discount')).toList();
      expect(discountRow, hasLength(1));
      expect(discountRow.single.length, lessThanOrEqualTo(PaperWidth.mm58));
      expect(discountRow.single, endsWith('-500.00'));
    });
  });

  group('which settings leave this phone', () {
    test('the shop identity does', () {
      for (final key in [
        'business_name',
        'business_phone',
        'receipt_footer',
        'vat_enabled',
        'vat_rate',
        'account_opay',
        'account_moniepoint',
      ]) {
        expect(SettingsRepository.isShared(key), isTrue, reason: key);
      }
    });

    test('device state never does', () {
      // A printer pairs with one handset; cursors describe one phone's sync
      // progress; the cached role is one phone's permission. Any of these
      // syncing would let one device corrupt another.
      for (final key in [
        'printer_mac',
        'printer_name',
        'paper_width',
        'auto_print',
        'business_id',
        'member_role',
        'member_sees_profit',
        'sync_cursor_products',
        'sync_cursor_app_settings',
      ]) {
        expect(SettingsRepository.isShared(key), isFalse, reason: key);
      }
    });
  });
}
