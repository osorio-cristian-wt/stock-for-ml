import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../parties/party_form_sheet.dart';
import '../purchases/qty_cost_sheet.dart';
import 'sale_scan_screen.dart';

/// Nueva venta local — MISMO flujo que la compra: carrito de varios productos
/// (escáner continuo o búsqueda), cliente opcional (padrón propio o "sin
/// cliente") y depósito. Al confirmar, `create_local_sale` escribe todo en
/// UNA transacción: valida stock por línea y descuenta; si algo no alcanza,
/// error y no queda nada a medias.
class LocalSaleScreen extends ConsumerStatefulWidget {
  const LocalSaleScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LocalSaleScreen()),
    );
  }

  @override
  ConsumerState<LocalSaleScreen> createState() => _LocalSaleScreenState();
}

class _CartLine {
  _CartLine({required this.product, required this.qty, required this.price});

  final Product product;
  int qty;
  double price;

  double get total => qty * price;
}

class _LocalSaleScreenState extends ConsumerState<LocalSaleScreen> {
  final List<_CartLine> _lines = [];
  String? _customerId; // null = sin cliente
  String? _warehouseId; // null = principal
  bool _busy = false;

  double _suggestedPrice(Product p) =>
      ref.read(economicsByProductProvider)[p.id]?.salePrice ?? 0;

  void _addLine(Product p, int qty, double price) {
    setState(() {
      for (final l in _lines) {
        if (l.product.id == p.id) {
          l.qty += qty;
          l.price = price;
          return;
        }
      }
      _lines.add(_CartLine(product: p, qty: qty, price: price));
    });
  }

  Future<void> _scan() => SaleScanScreen.open(
        context,
        onAddLine: _addLine,
        suggestedPrice: _suggestedPrice,
      );

  Future<void> _search() async {
    final product = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProductSearchSheet(),
    );
    if (product == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QtyCostSheet(
        title: product.title,
        initialQty: 1,
        initialCost: _suggestedPrice(product),
        priceLabel: 'Precio unitario (ARS)',
        confirmLabel: 'Agregar a la venta',
        onConfirm: (qty, price) async => _addLine(product, qty, price),
      ),
    );
  }

  Future<void> _editLine(_CartLine line) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QtyCostSheet(
        title: line.product.title,
        initialQty: line.qty,
        initialCost: line.price,
        priceLabel: 'Precio unitario (ARS)',
        confirmLabel: 'Guardar',
        onConfirm: (qty, price) async => setState(() {
          line.qty = qty;
          line.price = price;
        }),
      ),
    );
  }

  Future<void> _pickCustomer() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _CustomerSheet(),
    );
    if (selected == null || !mounted) return;
    setState(() => _customerId = selected.isEmpty ? null : selected);
  }

  Future<void> _pickWarehouse() async {
    final warehouses =
        ref.read(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    if (warehouses.length < 2) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _WarehousePickSheet(warehouses: warehouses),
    );
    if (selected != null && mounted) setState(() => _warehouseId = selected);
  }

  Future<void> _confirm() async {
    if (_lines.isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(salesRepositoryProvider).createLocalSale(
            items: [
              for (final l in _lines)
                (productId: l.product.id, quantity: l.qty, unitPrice: l.price),
            ],
            customerId: _customerId,
            warehouseId: _warehouseId,
          );
      ref.invalidate(salesProvider);
      ref.invalidate(dashboardProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Venta registrada · stock actualizado')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        // ej. "stock insuficiente en el depósito…" — nada quedó a medias.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('No se registró la venta. ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    if (_lines.isEmpty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Descartar venta',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('El carrito se pierde. ¿Salir igual?',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Seguir acá', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final customers =
        ref.watch(customersProvider).valueOrNull ?? const <Customer>[];
    final warehouses =
        ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    Customer? customer;
    for (final c in customers) {
      if (c.id == _customerId) customer = c;
    }
    Warehouse? warehouse;
    Warehouse? defaultWarehouse;
    for (final w in warehouses) {
      if (w.id == _warehouseId) warehouse = w;
      if (w.isDefault) defaultWarehouse = w;
    }
    final wh = warehouse ?? defaultWarehouse;
    final total = _lines.fold<double>(0, (a, l) => a + l.total);

    return PopScope(
      canPop: _lines.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Nueva venta')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _scan,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Escanear productos'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
            children: [
              SurfaceCard(
                child: Column(
                  children: [
                    _HeaderRow(
                      icon: Icons.person_outline,
                      label: 'Cliente',
                      value: customer?.name ?? 'Sin cliente',
                      muted: customer == null,
                      onTap: _pickCustomer,
                    ),
                    if (warehouses.length > 1) ...[
                      const Divider(height: 18, color: AppColors.border),
                      _HeaderRow(
                        icon: Icons.warehouse_outlined,
                        label: 'Depósito',
                        value: wh == null
                            ? 'Principal'
                            : (wh.isDefault ? '${wh.name} · principal' : wh.name),
                        muted: false,
                        onTap: _pickWarehouse,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Productos · ${_lines.length}',
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _search,
                        icon: const Icon(Icons.search, size: 16),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        label: const Text('Buscar'),
                      ),
                    ],
                  ),
                  Text(Fmt.ars(total),
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ],
              ),
              const SizedBox(height: 10),
              if (_lines.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: EmptyState(
                    icon: Icons.point_of_sale_rounded,
                    title: 'Sin productos',
                    message:
                        'Escaneá o buscá los productos que estás vendiendo.',
                  ),
                )
              else
                for (final l in _lines) ...[
                  _CartRow(
                    line: l,
                    onEdit: () => _editLine(l),
                    onRemove: () => setState(() => _lines.remove(l)),
                  ),
                  const SizedBox(height: 9),
                ],
              if (_lines.isNotEmpty) ...[
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _confirm,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.onPrimary),
                        )
                      : Text('Registrar venta · ${Fmt.ars(total)}'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.muted,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: muted ? AppColors.textMuted : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

class _CartRow extends StatelessWidget {
  const _CartRow({
    required this.line,
    required this.onEdit,
    required this.onRemove,
  });

  final _CartLine line;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = line.product;
    final overStock = line.qty > p.currentStock;
    return SurfaceCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: onEdit,
      borderColor: overStock ? AppColors.danger : AppColors.border,
      child: Row(
        children: [
          ProductThumb(imageUrl: p.imageUrl, size: 40, radius: 10),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text(
                  '${line.qty} u · ${Fmt.ars(line.price)} c/u'
                  '${overStock ? ' · supera el disponible (${p.currentStock})' : ''}',
                  style: TextStyle(
                      fontSize: 11,
                      color: overStock ? AppColors.danger : AppColors.textMuted),
                ),
              ],
            ),
          ),
          Text(Fmt.ars(line.total),
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// Elegir cliente: "Sin cliente" (pop ''), lista del padrón o alta con la
/// ventana compartida de proveedores/clientes.
class _CustomerSheet extends ConsumerStatefulWidget {
  const _CustomerSheet();

  @override
  ConsumerState<_CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends ConsumerState<_CustomerSheet> {
  bool _busy = false;

  Future<void> _create() async {
    final data = await PartyFormSheet.show(context, title: 'Nuevo cliente');
    if (data == null || !mounted) return;
    setState(() => _busy = true);
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    try {
      final created = await ref.read(customersRepositoryProvider).create(
            Customer(
              id: '',
              profileId: userId,
              name: data.name,
              legalName: data.legalName,
              taxId: data.taxId,
              phone: data.phone,
              email: data.email,
            ),
          );
      ref.invalidate(customersProvider);
      if (mounted) Navigator.of(context).pop(created.id);
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('No se pudo crear. ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Cliente',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            SurfaceCard(
              radius: 13,
              padding: const EdgeInsets.all(12),
              onTap: () => Navigator.of(context).pop(''),
              child: const Row(
                children: [
                  Icon(Icons.person_off_outlined,
                      size: 18, color: AppColors.textSecondary),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Sin cliente',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            customersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.4, color: AppColors.primary),
                  ),
                ),
              ),
              error: (e, _) => Text('No se pudieron cargar los clientes. $e',
                  style: const TextStyle(fontSize: 12, color: AppColors.danger)),
              data: (customers) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final c in customers) ...[
                    SurfaceCard(
                      radius: 13,
                      padding: const EdgeInsets.all(12),
                      onTap: () => Navigator.of(context).pop(c.id),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                                if (c.taxId != null || c.legalName != null)
                                  Text(
                                    [
                                      if (c.legalName != null) c.legalName,
                                      if (c.taxId != null) c.taxId,
                                    ].join(' · '),
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.person_add_alt, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.border),
              ),
              label: const Text('Nuevo cliente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarehousePickSheet extends StatelessWidget {
  const _WarehousePickSheet({required this.warehouses});

  final List<Warehouse> warehouses;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Depósito de la venta',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            for (final w in warehouses) ...[
              SurfaceCard(
                radius: 13,
                padding: const EdgeInsets.all(12),
                onTap: () => Navigator.of(context).pop(w.id),
                child: Row(
                  children: [
                    Icon(
                      w.isDefault
                          ? Icons.local_shipping_rounded
                          : Icons.warehouse_outlined,
                      size: 18,
                      color:
                          w.isDefault ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        w.isDefault ? '${w.name} · principal' : w.name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

/// Búsqueda manual (misma idea que en la compra): devuelve el producto elegido.
class _ProductSearchSheet extends ConsumerStatefulWidget {
  const _ProductSearchSheet();

  @override
  ConsumerState<_ProductSearchSheet> createState() =>
      _ProductSearchSheetState();
}

class _ProductSearchSheetState extends ConsumerState<_ProductSearchSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final q = _query.toLowerCase();
    final results = q.isEmpty
        ? all.take(20).toList()
        : all
            .where((p) =>
                p.title.toLowerCase().contains(q) ||
                (p.sku?.toLowerCase().contains(q) ?? false) ||
                (p.gtin?.toLowerCase().contains(q) ?? false) ||
                (p.brand?.toLowerCase().contains(q) ?? false))
            .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Buscar por título, SKU o marca…',
                  prefixIcon:
                      Icon(Icons.search, color: AppColors.textFaint, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: results.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 22),
                        child: Text('Sin coincidencias.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 13, color: AppColors.textMuted)),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = results[i];
                          return SurfaceCard(
                            radius: 13,
                            padding: const EdgeInsets.all(10),
                            onTap: () => Navigator.of(context).pop(p),
                            child: Row(
                              children: [
                                ProductThumb(
                                    imageUrl: p.imageUrl, size: 36, radius: 9),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(p.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary)),
                                      Text(
                                        'stock ${p.currentStock}'
                                        '${p.sku != null ? ' · ${p.sku}' : ''}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textMuted),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.add_circle_outline,
                                    color: AppColors.primary, size: 20),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
