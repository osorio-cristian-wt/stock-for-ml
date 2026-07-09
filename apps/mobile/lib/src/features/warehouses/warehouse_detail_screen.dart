import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../products/product_detail_screen.dart';
import '../stock_adjustment/transfer_sheet.dart';

/// Vista de UN depósito: qué productos tiene (disponible + buckets), acción de
/// transferir hacia otro depósito y el historial de movimientos del depósito.
/// Todo reactivo (product_stock y stock_movements están en realtime).
class WarehouseDetailScreen extends ConsumerWidget {
  const WarehouseDetailScreen({super.key, required this.warehouseId});

  final String warehouseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final warehouses =
        ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    Warehouse? warehouse;
    for (final w in warehouses) {
      if (w.id == warehouseId) {
        warehouse = w;
        break;
      }
    }
    final stockAsync = ref.watch(stockInWarehouseProvider(warehouseId));

    return Scaffold(
      appBar: AppBar(title: Text(warehouse?.name ?? 'Depósito')),
      body: stockAsync.when(
        loading: () => const Loading(),
        error: (e, _) => InlineError(
          message: '$e',
          onRetry: () => ref.invalidate(stockInWarehouseProvider(warehouseId)),
        ),
        data: (rows) {
          final withStock = rows
              .where((s) => s.onHand != 0 || s.reserved != 0 || s.incoming != 0)
              .toList()
            ..sort((a, b) => b.available.compareTo(a.available));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: [
              if (warehouse != null) _HeaderCard(warehouse: warehouse, rows: withStock),
              const SizedBox(height: 12),
              _ProductsCard(
                warehouseId: warehouseId,
                rows: withStock,
                canTransfer: warehouses.length > 1,
              ),
              const SizedBox(height: 12),
              _WarehouseHistoryCard(warehouseId: warehouseId),
            ],
          );
        },
      ),
    );
  }
}

/// Chips de rol (principal/despacho, vendible) + totales de los buckets.
class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.warehouse, required this.rows});

  final Warehouse warehouse;
  final List<ProductStock> rows;

  @override
  Widget build(BuildContext context) {
    final available = rows.fold<int>(0, (s, r) => s + r.available);
    final reserved = rows.fold<int>(0, (s, r) => s + r.reserved);
    final incoming = rows.fold<int>(0, (s, r) => s + r.incoming);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (warehouse.isDefault) ...[
                TagChip('Principal · despacho',
                    color: AppColors.primary,
                    background: AppColors.primarySoft,
                    bold: true),
                const SizedBox(width: 6),
              ],
              TagChip(warehouse.isSellable ? 'Vendible' : 'No vendible'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Total(label: 'Disponible', value: available,
                    color: AppColors.primary),
              ),
              Expanded(child: _Total(label: 'Reservado', value: reserved)),
              Expanded(child: _Total(label: 'En camino', value: incoming)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.value, this.color});

  final String label;
  final int value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        const SizedBox(height: 2),
        Text('$value u.',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color ?? AppColors.textPrimary)),
      ],
    );
  }
}

/// Productos con stock en este depósito. Tap → detalle; ícono → transferir
/// desde acá (origen preseleccionado).
class _ProductsCard extends ConsumerWidget {
  const _ProductsCard({
    required this.warehouseId,
    required this.rows,
    required this.canTransfer,
  });

  final String warehouseId;
  final List<ProductStock> rows;
  final bool canTransfer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products =
        ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Productos en este depósito',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            const Text('Este depósito no tiene stock cargado.',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted))
          else
            for (var i = 0; i < rows.length; i++) ...[
              _ProductRow(
                stock: rows[i],
                product: byId[rows[i].productId],
                onTransfer: canTransfer && byId[rows[i].productId] != null
                    ? () => TransferSheet.show(
                          context,
                          product: byId[rows[i].productId]!,
                          fromWarehouseId: warehouseId,
                        )
                    : null,
              ),
              if (i != rows.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 9),
                  child: Divider(height: 1, color: AppColors.border),
                ),
            ],
        ],
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.stock, this.product, this.onTransfer});

  final ProductStock stock;
  final Product? product;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    final p = product;
    return InkWell(
      onTap: p == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailScreen(productId: p.id),
                ),
              ),
      child: Row(
        children: [
          ProductThumb(imageUrl: p?.imageUrl, size: 40, radius: 10),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p?.title ?? 'Producto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (stock.reserved != 0)
                      TagChip('Reservado ${stock.reserved}',
                          color: AppColors.warning,
                          background: AppColors.warningSoft),
                    if (stock.incoming != 0)
                      TagChip('En camino ${stock.incoming}'),
                    if (stock.reserved == 0 && stock.incoming == 0)
                      Text(p?.sku ?? '',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${stock.available} disp.',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          if (onTransfer != null)
            IconButton(
              onPressed: onTransfer,
              tooltip: 'Transferir',
              icon: const Icon(Icons.swap_horiz_rounded,
                  size: 20, color: AppColors.primary),
            ),
        ],
      ),
    );
  }
}

/// Historial del depósito: el ledger completo (incluye reservas/despachos de
/// ML, que sí son relevantes acá), con el producto y el bucket afectado.
class _WarehouseHistoryCard extends ConsumerWidget {
  const _WarehouseHistoryCard({required this.warehouseId});

  final String warehouseId;

  (IconData, String) _describe(StockMovement m) => switch (m.reason) {
        StockReason.purchase ||
        StockReason.purchaseReceived =>
          (Icons.local_shipping_outlined, 'Compra'),
        StockReason.purchaseOrdered =>
          (Icons.schedule_outlined, 'Pedido a proveedor'),
        StockReason.sale => (Icons.shopping_bag_outlined, 'Venta'),
        StockReason.reserve => (Icons.lock_outline, 'Reserva (venta ML)'),
        StockReason.dispatch => (Icons.local_post_office_outlined, 'Despacho'),
        StockReason.cancellation => (Icons.cancel_outlined, 'Cancelación'),
        StockReason.returned => (Icons.undo_rounded, 'Devolución'),
        StockReason.bounce => (Icons.u_turn_left_rounded, 'Rebote de envío'),
        StockReason.loss => (Icons.report_gmailerrorred_outlined, 'Pérdida'),
        StockReason.transfer => (
            Icons.swap_horiz_rounded,
            m.delta >= 0 ? 'Transferencia (entrada)' : 'Transferencia (salida)'
          ),
        StockReason.initialSync => (Icons.flag_outlined, 'Stock inicial'),
        StockReason.fullSync => (Icons.sync_rounded, 'Espejo Full (ML)'),
        StockReason.fullInbound =>
          (Icons.local_shipping_outlined, 'Salida a Full (atribuida)'),
        StockReason.adjustment => (Icons.tune_rounded, 'Ajuste'),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final movements =
        ref.watch(warehouseMovementsProvider(warehouseId)).valueOrNull ??
            const <StockMovement>[];
    final products =
        ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final titleById = {for (final p in products) p.id: p.title};
    if (movements.isEmpty) return const SizedBox.shrink();

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Historial del depósito',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const SizedBox(height: 12),
          for (var i = 0; i < movements.length; i++) ...[
            _MovementRow(
              movement: movements[i],
              describe: _describe(movements[i]),
              productTitle: titleById[movements[i].productId],
            ),
            if (i != movements.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 9),
                child: Divider(height: 1, color: AppColors.border),
              ),
          ],
        ],
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({
    required this.movement,
    required this.describe,
    this.productTitle,
  });

  final StockMovement movement;
  final (IconData, String) describe;
  final String? productTitle;

  @override
  Widget build(BuildContext context) {
    final m = movement;
    final (icon, label) = describe;
    final positive = m.delta >= 0;
    final bucketTag = switch (m.bucket) {
      StockBucket.reserved => ' · reservado',
      StockBucket.incoming => ' · en camino',
      StockBucket.onHand => '',
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label$bucketTag',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              if (productTitle != null)
                Text(productTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('${positive ? '+' : '−'}${m.delta.abs()} u',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: positive ? AppColors.primary : AppColors.danger)),
            Text(Fmt.shortDate(m.createdAt),
                style:
                    const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
      ],
    );
  }
}
