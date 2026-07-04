import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_db.g.dart';

/// Cola local de operaciones pendientes de subir (etapa B1 de
/// docs/analisis-cola-offline.md): cuando una venta/transferencia/ajuste/
/// cierre de compra se confirma sin red, queda acá y el worker la sube al
/// reconectar. El [id] es el MISMO uuid idempotente que viaja al RPC
/// (p_sale_id / p_reference / p_movement_id), así un reintento duplicado es
/// no-op en el server.
class PendingOps extends Table {
  TextColumn get id => text()();

  /// sale | purchase_close | transfer | adjust (ver [PendingOpKind]).
  TextColumn get kind => text()();

  /// JSON con los parámetros del RPC (lo interpreta PendingOpsService).
  TextColumn get payload => text()();

  /// Resumen legible armado AL ENCOLAR (con los títulos en memoria), para
  /// listar la cola sin necesidad de resolver productos estando offline.
  TextColumn get summary => text()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// pending | error. `error` = el server la rechazó al sincronizar (ej.
  /// stock insuficiente horas después); sale del drenado automático y espera
  /// Reintentar/Descartar del usuario.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Base local (sqlite vía drift). Hoy solo aloja la cola offline; si aparece
/// más estado local (cachés, borradores), va acá.
@DriftDatabase(tables: [PendingOps])
class AppDb extends _$AppDb {
  AppDb() : super(driftDatabase(name: 'stock_for_ml'));

  /// Para tests: `AppDb.forTesting(NativeDatabase.memory())`.
  AppDb.forTesting(super.e);

  @override
  int get schemaVersion => 1;
}
