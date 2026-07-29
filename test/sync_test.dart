import 'package:flutter_test/flutter_test.dart';
import 'package:shoppadi/core/db/database.dart';
import 'package:shoppadi/core/sync/auth_service.dart';
import 'package:shoppadi/core/sync/payloads.dart';
import 'package:shoppadi/core/sync/sync_engine.dart';

const _business = 'b-1';

void main() {
  group('retry backoff', () {
    test('the first send is not delayed', () {
      expect(retryDelay(0), Duration.zero);
    });

    test('each failure waits longer', () {
      expect(retryDelay(1), const Duration(seconds: 5));
      expect(retryDelay(2), const Duration(seconds: 10));
      expect(retryDelay(3), const Duration(seconds: 20));
    });

    test('the wait is capped so a long outage never parks it for hours', () {
      expect(retryDelay(20), const Duration(seconds: 300));
    });

    test('rows are eventually abandoned rather than blocking the queue', () {
      expect(maxSyncAttempts, lessThanOrEqualTo(10));
      expect(retryDelay(maxSyncAttempts).inSeconds, lessThanOrEqualTo(300));
    });
  });

  group('being offline is not a failure', () {
    test('network errors are recognised', () {
      expect(isOfflineError(Exception('Failed host lookup: supabase.co')), isTrue);
      expect(isOfflineError(Exception('Connection refused')), isTrue);
      expect(isOfflineError(Exception('Network is unreachable')), isTrue);
    });

    test('a server rejection is a real error', () {
      expect(isOfflineError(Exception('row violates row-level security')),
          isFalse);
      expect(isOfflineError(Exception('duplicate key value')), isFalse);
    });
  });

  group('status wording', () {
    test('says what an owner needs to know', () {
      expect(const SyncStatus(phase: SyncPhase.idle).label,
          'Everything backed up');
      expect(const SyncStatus(phase: SyncPhase.idle, pending: 3).label,
          '3 waiting');
      expect(const SyncStatus(phase: SyncPhase.offline, pending: 2).label,
          '2 waiting for signal');
      expect(const SyncStatus(phase: SyncPhase.notSignedIn).label,
          'Sign in to back up');
    });
  });

  group('payloads', () {
    final product = Product(
      id: 'p1',
      name: 'Rice 5kg',
      baseUnit: 'piece',
      costPrice: 900000,
      sellingPrice: 1050000,
      quantity: 8,
      lowStockLevel: 2,
      vatExempt: false,
      isActive: true,
      updatedAt: DateTime.utc(2026, 7, 25, 10),
    );

    test('every row carries the business id RLS checks', () {
      expect(Payloads.product(product, _business)['business_id'], _business);
    });

    test('money stays an integer — no floats near naira', () {
      final json = Payloads.product(product, _business);
      expect(json['cost_price'], isA<int>());
      expect(json['selling_price'], 1050000);
    });

    test('column names are the snake_case Postgres expects', () {
      final json = Payloads.product(product, _business);
      expect(json.keys, contains('low_stock_level'));
      expect(json.keys, contains('selling_price'));
      expect(json.keys, isNot(contains('sellingPrice')));
    });

    test('a sale date is sent as a bare day, not a timestamp', () {
      final sale = Sale(
        id: 's1',
        receiptNo: 41,
        subtotal: 280000,
        discount: 0,
        vatAmount: 0,
        total: 280000,
        amountPaid: 280000,
        paymentMethod: 'cash',
        status: 'completed',
        saleDate: DateTime(2026, 7, 5, 14, 30),
      );
      expect(Payloads.sale(sale, _business)['sale_date'], '2026-07-05');
    });

    test('stored JSON is sent as JSON, not as a quoted string', () {
      final row = Return(
        id: 'r1',
        saleId: 's1',
        items: '[{"name":"Rice 5kg","qty":1,"value":1050000}]',
        restock: true,
        refundMethod: 'cash',
        amount: 1050000,
        createdAt: DateTime.utc(2026, 7, 25),
      );
      final json = Payloads.returnRow(row, _business);
      expect(json['items'], isA<List<dynamic>>());
      expect((json['items'] as List).first['name'], 'Rice 5kg');
    });
  });

  group('phone normalising for sign-in', () {
    test('local, international and padded forms all agree', () {
      expect(AuthService.normalisePhone('08031234567'), '+2348031234567');
      expect(AuthService.normalisePhone('8031234567'), '+2348031234567');
      expect(AuthService.normalisePhone('+234 803 123 4567'), '+2348031234567');
      expect(AuthService.normalisePhone('002348031234567'), '+2348031234567');
    });
  });
}
