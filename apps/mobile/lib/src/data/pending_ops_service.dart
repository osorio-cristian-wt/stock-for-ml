import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/errors.dart';
import 'local/app_db.dart';
import 'pending_ops_repository.dart';
import 'queries.dart';
import 'sales_repository.dart';
import 'supabase_providers.dart';

/// Worker de la cola offline (etapa B1 de docs/analisis-cola-offline.md):
/// drena `pending_ops` en orden FIFO al abrir la app, al recuperar
/// conectividad, al volver del segundo plano y en el reintento manual.
/// Cada RPC es idempotente por el id del op, así que un duplicado (subió
/// pero se cortó la respuesta) es no-op en el server.
class PendingOpsService with WidgetsBindingObserver {
  PendingOpsService(this._ref);

  final Ref _ref;

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _started = false;
  bool _draining = false;

  /// Arranque único (desde el init de la app): registra los triggers y hace
  /// el primer drenado por si quedaron ops de una sesión anterior.
  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online) drain();
    });
    drain();
  }

  void dispose() {
    _connSub?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) drain();
  }

  // ── Encolado (una API tipada por kind; el JSON es interno) ──────────

  Future<void> enqueueSale({
    required String saleId,
    required List<LocalSaleLine> items,
    String? customerId,
    String? warehouseId,
    String? note,
    required String summary,
  }) {
    return _enqueue(saleId, PendingOpKind.sale, summary, {
      'items': [
        for (final l in items)
          {
            'product_id': l.productId,
            'quantity': l.quantity,
            'unit_price': l.unitPrice,
            'warehouse_id': l.warehouseId,
          },
      ],
      'customer_id': customerId,
      'warehouse_id': warehouseId,
      'note': note,
    });
  }

  Future<void> enqueuePurchaseClose({
    required String purchaseId,
    required String summary,
  }) {
    // El id del op = purchase_id: close_purchase ya es idempotente por
    // estado, y así un doble encolado del mismo cierre tampoco duplica.
    return _enqueue(purchaseId, PendingOpKind.purchaseClose, summary, {
      'purchase_id': purchaseId,
    });
  }

  Future<void> enqueueTransfer({
    required String reference,
    required String productId,
    required String fromWarehouseId,
    required String toWarehouseId,
    required int qty,
    String? note,
    required String summary,
  }) {
    return _enqueue(reference, PendingOpKind.transfer, summary, {
      'product_id': productId,
      'from_warehouse_id': fromWarehouseId,
      'to_warehouse_id': toWarehouseId,
      'qty': qty,
      'note': note,
    });
  }

  Future<void> enqueueAdjust({
    required String movementId,
    required String productId,
    required int delta,
    required StockReason reason,
    String? note,
    String? warehouseId,
    required String summary,
  }) {
    return _enqueue(movementId, PendingOpKind.adjust, summary, {
      'product_id': productId,
      'delta': delta,
      'reason': reason.wire,
      'note': note,
      'warehouse_id': warehouseId,
    });
  }

  Future<void> _enqueue(
      String id, String kind, String summary, Map<String, Object?> payload) async {
    await _ref.read(pendingOpsRepositoryProvider).enqueue(
        id: id, kind: kind, payload: jsonEncode(payload), summary: summary);
    // Por si la red volvió entre el fallo y el encolado.
    drain();
  }

  // ── Drenado ─────────────────────────────────────────────────────────

  /// Sube las ops pendientes en orden. Corta al primer fallo de conectividad
  /// (todo sigue `pending`); un rechazo del server marca el op en `error`
  /// (visible con detalle, retry manual) y sigue con el próximo.
  Future<void> drain() async {
    if (_draining) return;
    // Sin sesión (logout / candado) no hay RLS válida: no intentar.
    if (_ref.read(supabaseClientProvider).auth.currentSession == null) return;
    _draining = true;
    var uploaded = false;
    try {
      final repo = _ref.read(pendingOpsRepositoryProvider);
      for (final op in await repo.pendingOrdered()) {
        try {
          await _execute(op);
          await repo.delete(op.id);
          uploaded = true;
        } catch (e) {
          if (AppErrors.isOffline(e)) return;
          await repo.markError(op, e);
        }
      }
    } finally {
      _draining = false;
      if (uploaded) {
        // Compras/transferencias/stock llegan por realtime; estos dos son
        // FutureProviders y necesitan el empujón.
        _ref.invalidate(salesProvider);
        _ref.invalidate(dashboardProvider);
      }
    }
  }

  Future<void> _execute(PendingOp op) async {
    final p = jsonDecode(op.payload) as Map<String, dynamic>;
    switch (op.kind) {
      case PendingOpKind.sale:
        await _ref.read(salesRepositoryProvider).createLocalSale(
              items: [
                for (final l in p['items'] as List)
                  (
                    productId: l['product_id'] as String,
                    quantity: l['quantity'] as int,
                    unitPrice: (l['unit_price'] as num).toDouble(),
                    warehouseId: l['warehouse_id'] as String?,
                  ),
              ],
              customerId: p['customer_id'] as String?,
              warehouseId: p['warehouse_id'] as String?,
              note: p['note'] as String?,
              saleId: op.id,
            );
      case PendingOpKind.purchaseClose:
        await _ref
            .read(purchasesRepositoryProvider)
            .close(p['purchase_id'] as String);
      case PendingOpKind.transfer:
        await _ref.read(inventoryRepositoryProvider).transferStock(
              productId: p['product_id'] as String,
              fromWarehouseId: p['from_warehouse_id'] as String,
              toWarehouseId: p['to_warehouse_id'] as String,
              qty: p['qty'] as int,
              note: p['note'] as String?,
              reference: op.id,
            );
      case PendingOpKind.adjust:
        final reason = StockReason.values
            .firstWhere((r) => r.wire == p['reason'] as String);
        await _ref.read(productsRepositoryProvider).applyStockMovement(
              productId: p['product_id'] as String,
              delta: p['delta'] as int,
              reason: reason,
              note: p['note'] as String?,
              warehouseId: p['warehouse_id'] as String?,
              movementId: op.id,
            );
      default:
        throw AppException('Operación desconocida en la cola: ${op.kind}');
    }
  }
}

// ── Providers ─────────────────────────────────────────────────────────

/// Base sqlite local (una sola instancia por app).
final appDbProvider = Provider<AppDb>((ref) {
  final db = AppDb();
  ref.onDispose(db.close);
  return db;
});

final pendingOpsRepositoryProvider = Provider<PendingOpsRepository>((ref) {
  return PendingOpsRepository(ref.watch(appDbProvider));
});

final pendingOpsServiceProvider = Provider<PendingOpsService>((ref) {
  final service = PendingOpsService(ref);
  ref.onDispose(service.dispose);
  return service;
});

/// La cola completa, FIFO y reactiva — sección "Pendientes de subir".
final pendingOpsProvider = StreamProvider<List<PendingOp>>((ref) {
  return ref.watch(pendingOpsRepositoryProvider).watchAll();
});

/// Cantidad en cola — badge del tab Movimientos.
final pendingOpsCountProvider = Provider<int>((ref) {
  return ref.watch(pendingOpsProvider).valueOrNull?.length ?? 0;
});
