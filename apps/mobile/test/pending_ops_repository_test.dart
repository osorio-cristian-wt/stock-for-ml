import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stock_for_ml/src/data/local/app_db.dart';
import 'package:stock_for_ml/src/data/pending_ops_repository.dart';

void main() {
  late AppDb db;
  late PendingOpsRepository repo;

  setUp(() {
    db = AppDb.forTesting(NativeDatabase.memory());
    repo = PendingOpsRepository(db);
  });

  tearDown(() => db.close());

  test('encola en orden FIFO y el reintento con el mismo id no duplica',
      () async {
    await repo.enqueue(
        id: 'op-1', kind: PendingOpKind.sale, payload: '{}', summary: 'Venta 1');
    await repo.enqueue(
        id: 'op-2',
        kind: PendingOpKind.transfer,
        payload: '{}',
        summary: 'Transferencia');
    // Doble confirm offline con el MISMO id → insertOrIgnore, no duplica.
    await repo.enqueue(
        id: 'op-1', kind: PendingOpKind.sale, payload: '{}', summary: 'Venta 1');

    final pending = await repo.pendingOrdered();
    expect(pending.map((o) => o.id), ['op-1', 'op-2']);
    expect(pending.first.status, PendingOpStatus.pending);
    expect(pending.first.attempts, 0);
  });

  test('markError la saca del drenado; resetToPending la devuelve', () async {
    await repo.enqueue(
        id: 'op-1', kind: PendingOpKind.sale, payload: '{}', summary: 'Venta');
    var op = (await repo.pendingOrdered()).single;

    await repo.markError(op, Exception('stock insuficiente'));
    expect(await repo.pendingOrdered(), isEmpty,
        reason: 'un op en error no se drena automáticamente');

    final all = await repo.watchAll().first;
    op = all.single;
    expect(op.status, PendingOpStatus.error);
    expect(op.lastError, contains('stock insuficiente'));
    expect(op.attempts, 1);

    await repo.resetToPending(op.id);
    final again = (await repo.pendingOrdered()).single;
    expect(again.status, PendingOpStatus.pending);
    expect(again.lastError, isNull);
  });

  test('delete la elimina (subida OK o descarte del usuario)', () async {
    await repo.enqueue(
        id: 'op-1', kind: PendingOpKind.adjust, payload: '{}', summary: 'Ajuste');
    await repo.delete('op-1');
    expect(await repo.watchAll().first, isEmpty);
  });
}
