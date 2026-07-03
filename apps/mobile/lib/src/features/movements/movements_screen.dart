import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/widgets/app_widgets.dart';
import '../scan/code_scanner_screen.dart';

/// Tab Movimientos · transferencia de stock entre depósitos, estilo "carga de
/// compra": se elige EXPLÍCITAMENTE de qué depósito sale y a cuál llega, se
/// marcan cantidades sobre los productos con stock en el origen (las filas con
/// movimiento ≠ 0 se resaltan) — a mano o escaneando — y al confirmar se
/// muestra el detalle de lo movido. Solo control interno: una transferencia
/// balanceada no cambia el disponible total, así que no empuja nada a ML.
class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({super.key});

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  String? _fromId;
  String? _toId;

  /// productId → unidades a mover (solo > 0 cuentan).
  final Map<String, int> _qty = {};
  bool _busy = false;

  bool get _ready => _fromId != null && _toId != null && _fromId != _toId;

  int _totalUnits() => _qty.values.fold(0, (a, b) => a + b);

  List<ProductStock> _movable(List<ProductStock> rows) =>
      rows.where((s) => s.available > 0).toList()
        ..sort((a, b) => b.available.compareTo(a.available));

  void _setQty(ProductStock s, int value) {
    setState(() {
      final v = value.clamp(0, s.available);
      if (v == 0) {
        _qty.remove(s.productId);
      } else {
        _qty[s.productId] = v;
      }
    });
  }

  void _swap() {
    setState(() {
      final f = _fromId;
      _fromId = _toId;
      _toId = f;
      _qty.clear();
    });
  }

  /// "Volver atrás" del movimiento en curso: limpia ruta y cantidades.
  void _reset() {
    setState(() {
      _fromId = null;
      _toId = null;
      _qty.clear();
    });
  }

  /// Reusa el escáner de compras: el código busca por SKU/GTIN entre los
  /// productos CON stock en el depósito de origen y suma +1 a su cantidad.
  Future<void> _scan(List<ProductStock> movable, Map<String, Product> products) async {
    final code = await CodeScannerScreen.scan(
      context,
      title: 'Escanear para mover',
      subtitle: 'Cada lectura suma +1 al producto en el depósito de origen.',
    );
    if (code == null || code.isEmpty || !mounted) return;

    final sc = ScannedCode.classify(code);
    final keys = {code.toLowerCase(), if (sc.gtin != null) sc.gtin!.toLowerCase()};
    ProductStock? hit;
    for (final s in movable) {
      final p = products[s.productId];
      if (p == null) continue;
      if (keys.contains(p.sku?.toLowerCase()) ||
          keys.contains(p.gtin?.toLowerCase())) {
        hit = s;
        break;
      }
    }
    if (hit == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('“$code” no tiene stock en el depósito de origen.')));
      return;
    }
    final current = _qty[hit.productId] ?? 0;
    if (current >= hit.available) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ya marcaste todo el disponible de ese producto.')));
      return;
    }
    await HapticFeedback.mediumImpact();
    _setQty(hit, current + 1);
  }

  Future<void> _confirm(
    Map<String, Product> products,
    Map<String, Warehouse> warehouses,
  ) async {
    final lines = _qty.entries.where((e) => e.value > 0).toList();
    if (lines.isEmpty || !_ready) return;
    setState(() => _busy = true);
    final repo = ref.read(inventoryRepositoryProvider);
    final moved = <(String title, int qty)>[];
    String? error;
    try {
      for (final e in lines) {
        await repo.transferStock(
          productId: e.key,
          fromWarehouseId: _fromId!,
          toWarehouseId: _toId!,
          qty: e.value,
        );
        moved.add((products[e.key]?.title ?? 'Producto', e.value));
      }
    } catch (e) {
      error = e.toString().split('\n').first;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      for (final (i, _) in moved.indexed) {
        _qty.remove(lines[i].key);
      }
    });
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => _SummarySheet(
        fromName: warehouses[_fromId]?.name ?? 'Origen',
        toName: warehouses[_toId]?.name ?? 'Destino',
        moved: moved,
        error: error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final warehouses =
        ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    final products = {
      for (final p
          in ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[])
        p.id: p,
    };
    final byId = {for (final w in warehouses) w.id: w};
    final stockRows = _ready
        ? (ref.watch(stockInWarehouseProvider(_fromId!)).valueOrNull ??
            const <ProductStock>[])
        : const <ProductStock>[];
    final movable = _movable(stockRows);
    final marked = _qty.entries.where((e) => e.value > 0).length;
    final units = _totalUnits();

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Movimientos',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  if (_fromId != null || _toId != null || _qty.isNotEmpty)
                    TextButton.icon(
                      onPressed: _reset,
                      icon: const Icon(Icons.close, size: 16),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary),
                      label: const Text('Cancelar'),
                    ),
                  if (_ready)
                    IconButton(
                      tooltip: 'Escanear producto',
                      onPressed: () => _scan(movable, products),
                      icon: const Icon(Icons.qr_code_scanner_rounded,
                          color: AppColors.primary),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _RouteCard(
                warehouses: warehouses,
                fromId: _fromId,
                toId: _toId,
                onFrom: (id) => setState(() {
                  _fromId = id;
                  _qty.clear();
                }),
                onTo: (id) => setState(() => _toId = id),
                onSwap: _swap,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: !_ready
                  ? const EmptyState(
                      icon: Icons.swap_horiz_rounded,
                      title: 'Elegí origen y destino',
                      message:
                          'Marcá de qué depósito sale el stock y a cuál llega. '
                          'Después seleccioná o escaneá los productos a mover.',
                    )
                  : movable.isEmpty
                      ? const EmptyState(
                          icon: Icons.inventory_2_outlined,
                          title: 'Sin stock disponible',
                          message:
                              'El depósito de origen no tiene productos con '
                              'stock disponible para mover.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                          itemCount: movable.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 9),
                          itemBuilder: (_, i) {
                            final s = movable[i];
                            return _MoveRow(
                              stock: s,
                              product: products[s.productId],
                              qty: _qty[s.productId] ?? 0,
                              onChanged: (v) => _setQty(s, v),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _ready && marked > 0
          ? SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: _busy ? null : () => _confirm(products, byId),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.onPrimary),
                        )
                      : Text('Mover $marked producto'
                          '${marked == 1 ? '' : 's'} · $units u.'),
                ),
              ),
            )
          : null,
    );
  }
}

/// "Sale de X → llega a Y", bien explícito, con botón para invertir.
class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.warehouses,
    required this.fromId,
    required this.toId,
    required this.onFrom,
    required this.onTo,
    required this.onSwap,
  });

  final List<Warehouse> warehouses;
  final String? fromId;
  final String? toId;
  final ValueChanged<String?> onFrom;
  final ValueChanged<String?> onTo;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    if (warehouses.length < 2) {
      return const SurfaceCard(
        child: Text(
          'Necesitás al menos 2 depósitos para mover stock. Creá otro desde '
          'Ajustes → Depósitos.',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
        ),
      );
    }
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Picker(
            label: 'SALE DE',
            icon: Icons.logout_rounded,
            warehouses: warehouses,
            selectedId: fromId,
            excludeId: null,
            onChanged: onFrom,
          ),
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.border, height: 22)),
              IconButton(
                tooltip: 'Invertir',
                onPressed: onSwap,
                icon: const Icon(Icons.swap_vert_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const Expanded(child: Divider(color: AppColors.border, height: 22)),
            ],
          ),
          _Picker(
            label: 'LLEGA A',
            icon: Icons.login_rounded,
            warehouses: warehouses,
            selectedId: toId,
            excludeId: fromId,
            onChanged: onTo,
          ),
        ],
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.icon,
    required this.warehouses,
    required this.selectedId,
    required this.excludeId,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final List<Warehouse> warehouses;
  final String? selectedId;
  final String? excludeId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: AppColors.textMuted)),
        ),
        Expanded(
          child: DropdownButtonFormField<String?>(
            value: selectedId,
            isExpanded: true,
            dropdownColor: AppColors.surface,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            icon: const Icon(Icons.expand_more, color: AppColors.textFaint),
            decoration: const InputDecoration(hintText: 'Elegí un depósito'),
            items: [
              for (final w in warehouses)
                if (w.id != excludeId)
                  DropdownMenuItem<String?>(
                    value: w.id,
                    child: Text(w.isDefault ? '${w.name} · principal' : w.name),
                  ),
            ],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

/// Fila de producto con stepper; se pinta (borde + fondo primario suave)
/// cuando tiene un movimiento marcado ≠ 0.
class _MoveRow extends StatelessWidget {
  const _MoveRow({
    required this.stock,
    required this.product,
    required this.qty,
    required this.onChanged,
  });

  final ProductStock stock;
  final Product? product;
  final int qty;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final marked = qty > 0;
    return SurfaceCard(
      radius: 14,
      padding: const EdgeInsets.all(11),
      color: marked ? AppColors.primarySoft : AppColors.surface,
      borderColor: marked ? AppColors.primary : AppColors.border,
      child: Row(
        children: [
          ProductThumb(imageUrl: product?.imageUrl, size: 40, radius: 10),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product?.title ?? 'Producto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text(
                  marked
                      ? 'mueve $qty de ${stock.available} disp.'
                      : '${stock.available} disp.',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: marked ? FontWeight.w600 : FontWeight.w400,
                    color: marked ? AppColors.primary : AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          _StepBtn(icon: Icons.remove, enabled: qty > 0, onTap: () => onChanged(qty - 1)),
          SizedBox(
            width: 34,
            child: Text('$qty',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: marked ? AppColors.primary : AppColors.textMuted)),
          ),
          _StepBtn(
              icon: Icons.add,
              enabled: qty < stock.available,
              onTap: () => onChanged(qty + 1)),
        ],
      ),
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({required this.icon, required this.enabled, required this.onTap});

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.borderStrong),
          ),
          child: Icon(icon,
              size: 17,
              color: enabled ? AppColors.textSecondary : AppColors.textFaint),
        ),
      ),
    );
  }
}

/// Detalle de lo movido, mostrado al confirmar.
class _SummarySheet extends StatelessWidget {
  const _SummarySheet({
    required this.fromName,
    required this.toName,
    required this.moved,
    this.error,
  });

  final String fromName;
  final String toName;
  final List<(String, int)> moved;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final units = moved.fold<int>(0, (a, m) => a + m.$2);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              error == null ? Icons.check_circle_rounded : Icons.error_outline,
              color: error == null ? AppColors.primary : AppColors.danger,
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              error == null
                  ? 'Movimiento realizado'
                  : 'Movimiento incompleto',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              '$fromName  →  $toName',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: 14),
            for (final (title, qty) in moved)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.swap_horiz_rounded,
                        size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13, color: AppColors.textBody)),
                    ),
                    Text('$qty u.',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ],
                ),
              ),
            if (moved.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Total: $units u.',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                moved.isEmpty
                    ? 'No se movió nada: $error'
                    : 'Algunas líneas no se movieron: $error',
                style: const TextStyle(fontSize: 12, color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Listo'),
            ),
          ],
        ),
      ),
    );
  }
}
