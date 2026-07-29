import 'database.dart';

/// Marks a row as needing to reach the server.
///
/// Only the table and id are stored, not a snapshot: the sync engine reads the
/// current row when it sends, so five quick edits to one product cost one
/// request instead of five, and a row edited while offline is never sent stale.
Future<void> enqueue(AppDatabase db, String table, String rowId) {
  return db.into(db.outbox).insert(
        OutboxCompanion.insert(
          targetTable: table,
          rowId: rowId,
          op: 'upsert',
          payload: '',
          createdAt: DateTime.now(),
        ),
      );
}
