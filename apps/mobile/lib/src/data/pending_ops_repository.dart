import 'package:drift/drift.dart';

import 'local/app_db.dart';

/// Valores de `pending_ops.kind` (los 4 de docs/analisis-cola-offline.md).
abstract final class PendingOpKind {
  static const sale = 'sale';
  static const purchaseClose = 'purchase_close';
  static const transfer = 'transfer';
  static const adjust = 'adjust';
}

/// Valores de `pending_ops.status`.
abstract final class PendingOpStatus {
  static const pending = 'pending';
  static const error = 'error';
}

/// CRUD de la cola offline local. El drenado vive en PendingOpsService; acá
/// solo el acceso a la tabla.
class PendingOpsRepository {
  PendingOpsRepository(this._db);

  final AppDb _db;

  /// Encola una operación confirmada sin red. `insertOrIgnore`: un doble
  /// confirm offline con el mismo id idempotente no duplica la fila.
  Future<void> enqueue({
    required String id,
    required String kind,
    required String payload,
    required String summary,
  }) {
    return _db.into(_db.pendingOps).insert(
          PendingOpsCompanion.insert(
            id: id,
            kind: kind,
            payload: payload,
            summary: summary,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// createdAt se guarda con precisión de segundo; el rowid desempata para
  /// que dos ops encoladas en el mismo segundo mantengan el orden de llegada.
  List<OrderingTerm Function(PendingOps)> get _fifo => [
        (t) => OrderingTerm.asc(t.createdAt),
        (t) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
      ];

  /// Toda la cola, FIFO — alimenta la sección "Pendientes de subir" y el
  /// badge (reactivo: drift re-emite en cada cambio).
  Stream<List<PendingOp>> watchAll() {
    return (_db.select(_db.pendingOps)..orderBy(_fifo)).watch();
  }

  /// Solo las pendientes, FIFO — lo que el worker drena en orden.
  Future<List<PendingOp>> pendingOrdered() {
    return (_db.select(_db.pendingOps)
          ..where((t) => t.status.equals(PendingOpStatus.pending))
          ..orderBy(_fifo))
        .get();
  }

  /// La operación ya vive en Supabase (o el usuario la descartó): se borra.
  Future<void> delete(String id) {
    return (_db.delete(_db.pendingOps)..where((t) => t.id.equals(id))).go();
  }

  /// El server la rechazó al sincronizar: queda visible con el detalle y
  /// fuera del drenado automático (retry solo manual).
  Future<void> markError(PendingOp op, Object error) {
    return (_db.update(_db.pendingOps)..where((t) => t.id.equals(op.id)))
        .write(PendingOpsCompanion(
      status: const Value(PendingOpStatus.error),
      lastError: Value('$error'),
      attempts: Value(op.attempts + 1),
    ));
  }

  /// Reintento manual: vuelve al estado pendiente (el worker la retoma).
  Future<void> resetToPending(String id) {
    return (_db.update(_db.pendingOps)..where((t) => t.id.equals(id)))
        .write(const PendingOpsCompanion(
      status: Value(PendingOpStatus.pending),
      lastError: Value(null),
    ));
  }
}
