import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../parties/party_form_sheet.dart';
import '../products/product_form_screen.dart';
import '../scan/code_scanner_screen.dart';
import 'purchase_scan_screen.dart';
import 'qty_cost_sheet.dart';

/// Load / review a purchase. Drafts are editable (choose supplier + warehouse,
/// scan/search products by SKU, set quantities); closing posts the stock.
class PurchaseEditScreen extends ConsumerStatefulWidget {
  const PurchaseEditScreen({super.key, required this.purchase});

  final Purchase purchase;

  @override
  ConsumerState<PurchaseEditScreen> createState() => _PurchaseEditScreenState();
}

class _PurchaseEditScreenState extends ConsumerState<PurchaseEditScreen> {
  late Purchase _p = widget.purchase;
  bool _busy = false;

  bool get _editable => _p.isDraft;

  Future<void> _pickSupplier() async {
    // '' = "no especificado" (clears the supplier); null = dismissed.
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SupplierSheet(),
    );
    if (selected == null || !mounted) return;
    final repo = ref.read(purchasesRepositoryProvider);
    await repo.updateHeader(
      _p.id,
      supplierId: selected.isEmpty ? null : selected,
      clearSupplier: selected.isEmpty,
    );
    final fresh = await repo.byId(_p.id);
    if (mounted) setState(() => _p = fresh);
  }

  Future<void> _pickWarehouse() async {
    final warehouses =
        ref.read(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    if (warehouses.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => _WarehouseSheet(warehouses: warehouses),
    );
    if (selected == null || !mounted) return;
    await ref.read(purchasesRepositoryProvider).updateHeader(_p.id, warehouseId: selected);
    if (mounted) setState(() => _p = _p.copyWith(warehouseId: selected));
  }

  Future<void> _addItem() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddItemSheet(purchaseId: _p.id),
    );
  }

  String _mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  /// Photo of the invoice → Claude Haiku (vision) → review/approve → add lines.
  Future<void> _scanInvoice() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
              title: const Text('Tomar foto',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
              title: const Text('Elegir de la galería',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => Navigator.of(context).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    final XFile? file = await ImagePicker()
        .pickImage(source: source, maxWidth: 2000, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Leyendo la factura…')),
    );
    try {
      final bytes = await file.readAsBytes();
      final data = await ref.read(purchasesRepositoryProvider).parseInvoice(
            imageBase64: base64Encode(bytes),
            mime: _mimeFor(file.path),
          );
      if (!mounted) return;
      setState(() => _busy = false);
      if (data == null || data['error'] != null) {
        messenger.showSnackBar(SnackBar(
            content: Text('No se pudo leer la factura. ${data?['error'] ?? ''}')));
        return;
      }
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _InvoiceReviewSheet(purchaseId: _p.id, data: data),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(SnackBar(content: Text('Error al leer la factura. $e')));
      }
    }
  }

  Future<void> _editItem(PurchaseItem item, Product? product) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QtyCostSheet(
        title: product?.title ?? 'Producto',
        initialQty: item.quantity,
        initialCost: item.unitCost,
        confirmLabel: 'Guardar',
        onConfirm: (qty, cost) async {
          await ref
              .read(purchasesRepositoryProvider)
              .updateItem(item.id, quantity: qty, unitCost: cost);
        },
      ),
    );
  }

  Future<void> _close(List<PurchaseItem> items) async {
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agregá al menos un producto.')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(purchasesRepositoryProvider).close(_p.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Compra cerrada · stock actualizado')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cerrar. $e')),
        );
      }
    }
  }

  Future<void> _discard(List<PurchaseItem> items) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Descartar compra',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Se eliminará este borrador y sus líneas.',
            style: TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(purchasesRepositoryProvider).cancel(_p.id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(purchaseItemsProvider(_p.id));
    final products = {
      for (final p in ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[])
        p.id: p,
    };
    final suppliers = {
      for (final s in ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[])
        s.id: s,
    };
    final warehouses =
        ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    final items = itemsAsync.valueOrNull ?? const <PurchaseItem>[];
    final total = items.fold<double>(0, (a, it) => a + it.lineTotal);

    Warehouse? selectedWarehouse;
    Warehouse? defaultWarehouse;
    for (final w in warehouses) {
      if (w.id == _p.warehouseId) selectedWarehouse = w;
      if (w.isDefault) defaultWarehouse = w;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_editable ? 'Nueva compra' : 'Compra'),
        actions: [
          if (_editable)
            IconButton(
              tooltip: 'Escanear factura',
              icon: const Icon(Icons.document_scanner_outlined,
                  color: AppColors.primary),
              onPressed: _busy ? null : _scanInvoice,
            ),
          if (_editable)
            IconButton(
              tooltip: 'Descartar',
              icon: const Icon(Icons.delete_outline, color: AppColors.textMuted),
              onPressed: () => _discard(items),
            ),
        ],
      ),
      floatingActionButton: _editable
          ? FloatingActionButton.extended(
              onPressed: () =>
                  PurchaseScanScreen.open(context, purchaseId: _p.id),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Escaneo continuo'),
            )
          : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            _HeaderCard(
              supplier: suppliers[_p.supplierId],
              warehouse: selectedWarehouse,
              defaultWarehouse: defaultWarehouse,
              editable: _editable,
              onPickSupplier: _pickSupplier,
              onPickWarehouse: _pickWarehouse,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Productos · ${items.length}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                if (_editable) ...[
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.search, size: 16),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    label: const Text('Buscar'),
                  ),
                ],
                const Spacer(),
                Text(
                  _p.currency == 'USD' ? Fmt.usd(total) : Fmt.ars(total),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: EmptyState(
                  icon: Icons.add_box_outlined,
                  title: 'Sin productos',
                  message: 'Escaneá o buscá un producto por SKU para agregarlo.',
                ),
              )
            else
              for (final it in items) ...[
                _ItemRow(
                  item: it,
                  product: products[it.productId],
                  currency: _p.currency,
                  editable: _editable,
                  onEdit: () => _editItem(it, products[it.productId]),
                  onRemove: () =>
                      ref.read(purchasesRepositoryProvider).removeItem(it.id),
                ),
                const SizedBox(height: 9),
              ],
            if (_editable) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : () => _close(items),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.onPrimary),
                      )
                    : const Text('Cerrar compra y actualizar stock'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.supplier,
    required this.warehouse,
    required this.defaultWarehouse,
    required this.editable,
    required this.onPickSupplier,
    required this.onPickWarehouse,
  });

  final Supplier? supplier;
  final Warehouse? warehouse;
  final Warehouse? defaultWarehouse;
  final bool editable;
  final VoidCallback onPickSupplier;
  final VoidCallback onPickWarehouse;

  @override
  Widget build(BuildContext context) {
    final wh = warehouse ?? defaultWarehouse;
    return SurfaceCard(
      child: Column(
        children: [
          _Row(
            icon: Icons.store_outlined,
            label: 'Proveedor',
            value: supplier?.name ?? 'Elegir proveedor',
            muted: supplier == null,
            onTap: editable ? onPickSupplier : null,
          ),
          const Divider(height: 18, color: AppColors.border),
          _Row(
            icon: Icons.warehouse_outlined,
            label: 'Depósito',
            value: wh == null
                ? 'Principal'
                : (wh.isDefault ? '${wh.name} · principal' : wh.name),
            muted: false,
            onTap: editable ? onPickWarehouse : null,
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    required this.muted,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
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
          if (onTap != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.product,
    required this.currency,
    required this.editable,
    required this.onEdit,
    required this.onRemove,
  });

  final PurchaseItem item;
  final Product? product;
  final String currency;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final costText =
        currency == 'USD' ? Fmt.usd(item.lineTotal) : Fmt.ars(item.lineTotal);
    return SurfaceCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      onTap: editable ? onEdit : null,
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
                Text('${item.quantity} u · ${currency == 'USD' ? Fmt.usd(item.unitCost) : Fmt.ars(item.unitCost)} c/u',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(costText,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          if (editable)
            IconButton(
              icon: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// Search products by SKU/title and add the chosen one (qty + unit cost), or
/// jump to product creation when the scanned SKU doesn't exist yet.
class _AddItemSheet extends ConsumerStatefulWidget {
  const _AddItemSheet({required this.purchaseId});

  final String purchaseId;

  @override
  ConsumerState<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends ConsumerState<_AddItemSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(Product p) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QtyCostSheet(
        title: p.title,
        initialQty: 1,
        initialCost: p.purchaseCost,
        onConfirm: (qty, cost) async {
          await ref.read(purchasesRepositoryProvider).addItem(
                purchaseId: widget.purchaseId,
                productId: p.id,
                quantity: qty,
                unitCost: cost,
              );
        },
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _createNew() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(initialSku: _query.isEmpty ? null : _query),
      ),
    );
    if (created == true && mounted) {
      // The new product arrives via the live stream; keep the search open so the
      // user can pick it.
      setState(() {});
    }
  }

  /// Live camera scan: an exact SKU/GTIN match jumps straight to the qty
  /// sheet; otherwise the code lands in the search box (create from there).
  Future<void> _scanCode() async {
    final code = await CodeScannerScreen.scan(
      context,
      title: 'Escanear producto',
      subtitle: 'Se busca por SKU o código de barras entre tus productos.',
    );
    if (code == null || code.isEmpty || !mounted) return;
    _search.text = code;
    setState(() => _query = code);
    final all = ref.read(productsStreamProvider).valueOrNull ?? const <Product>[];
    final key = code.toLowerCase();
    final exact = [
      for (final p in all)
        if (p.sku?.toLowerCase() == key || p.gtin?.toLowerCase() == key) p,
    ];
    if (exact.length == 1) await _pick(exact.first);
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
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v.trim()),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Escaneá o escribí el SKU / título…',
                  prefixIcon:
                      const Icon(Icons.search, color: AppColors.textFaint, size: 20),
                  suffixIcon: IconButton(
                    tooltip: 'Escanear con la cámara',
                    icon: const Icon(Icons.qr_code_scanner_rounded,
                        color: AppColors.primary, size: 20),
                    onPressed: _scanCode,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.42,
                ),
                child: results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 22),
                        child: Column(
                          children: [
                            const Text('Sin coincidencias.',
                                style: TextStyle(
                                    fontSize: 13, color: AppColors.textMuted)),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: _createNew,
                              icon: const Icon(Icons.add, size: 18),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                side: const BorderSide(color: AppColors.border),
                              ),
                              label: const Text('Crear producto nuevo'),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = results[i];
                          return _ProductPickRow(product: p, onTap: () => _pick(p));
                        },
                      ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _createNew,
                icon: const Icon(Icons.add, size: 18),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
                label: const Text('Producto nuevo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductPickRow extends StatelessWidget {
  const _ProductPickRow({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: 13,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          ProductThumb(imageUrl: product.imageUrl, size: 36, radius: 9),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (product.sku != null)
                  Text(product.sku!,
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
        ],
      ),
    );
  }
}

/// Reviews the items Claude extracted from an invoice photo. Each line is
/// matched against the live catalog by SKU/GTIN; the user approves which
/// matched lines to add. Unmatched lines are flagged to create manually.
class _InvoiceReviewSheet extends ConsumerStatefulWidget {
  const _InvoiceReviewSheet({required this.purchaseId, required this.data});

  final String purchaseId;
  final Map<String, dynamic> data;

  @override
  ConsumerState<_InvoiceReviewSheet> createState() => _InvoiceReviewSheetState();
}

class _InvoiceReviewSheetState extends ConsumerState<_InvoiceReviewSheet> {
  final Set<int> _excluded = {};
  bool _busy = false;

  Product? _match(List<Product> products, String? sku) {
    if (sku == null) return null;
    final key = sku.trim().toLowerCase();
    if (key.isEmpty) return null;
    for (final p in products) {
      if ((p.sku?.toLowerCase() == key) || (p.gtin?.toLowerCase() == key)) {
        return p;
      }
    }
    return null;
  }

  Future<void> _approve(List<_InvoiceLine> lines) async {
    final toAdd = [
      for (var i = 0; i < lines.length; i++)
        if (lines[i].product != null && !_excluded.contains(i)) lines[i],
    ];
    if (toAdd.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    final repo = ref.read(purchasesRepositoryProvider);
    try {
      for (final l in toAdd) {
        await repo.addItem(
          purchaseId: widget.purchaseId,
          productId: l.product!.id,
          quantity: l.quantity,
          unitCost: l.unitCost,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${toAdd.length} producto(s) agregado(s)')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudieron agregar. $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final rawItems = (widget.data['items'] as List?) ?? const [];
    final lines = <_InvoiceLine>[
      for (final raw in rawItems)
        if (raw is Map)
          _InvoiceLine(
            description: (raw['description'] as String?)?.trim() ?? 'Ítem',
            sku: (raw['sku'] as String?)?.trim(),
            quantity: _asInt(raw['quantity'], 1) < 1 ? 1 : _asInt(raw['quantity'], 1),
            unitCost: _asDouble(raw['unit_cost']),
            product: _match(products, raw['sku'] as String?),
          ),
    ];
    final supplier = (widget.data['supplier'] as String?)?.trim();
    final date = (widget.data['date'] as String?)?.trim();
    final matched = lines.where((l) => l.product != null).length;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text('Factura leída',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                [
                  if (supplier != null && supplier.isNotEmpty) supplier,
                  if (date != null && date.isNotEmpty) date,
                  '$matched/${lines.length} con coincidencia',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 14),
              if (lines.isEmpty)
                const Text('No se detectaron líneas en la factura.',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted))
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: lines.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      final hasMatch = l.product != null;
                      final selected = hasMatch && !_excluded.contains(i);
                      return SurfaceCard(
                        radius: 13,
                        padding: const EdgeInsets.all(11),
                        onTap: hasMatch
                            ? () => setState(() {
                                  if (_excluded.contains(i)) {
                                    _excluded.remove(i);
                                  } else {
                                    _excluded.add(i);
                                  }
                                })
                            : null,
                        child: Row(
                          children: [
                            Icon(
                              !hasMatch
                                  ? Icons.help_outline
                                  : (selected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank),
                              size: 20,
                              color: !hasMatch
                                  ? AppColors.textFaint
                                  : (selected
                                      ? AppColors.primary
                                      : AppColors.textMuted),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.product?.title ?? l.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary)),
                                  Text(
                                    hasMatch
                                        ? '${l.quantity} u · ${Fmt.usd(l.unitCost)} c/u'
                                        : 'Sin coincidencia${l.sku != null ? ' (SKU ${l.sku})' : ''} — creá el producto',
                                    style: const TextStyle(
                                        fontSize: 11, color: AppColors.textMuted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _busy ? null : () => _approve(lines),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.onPrimary),
                      )
                    : const Text('Agregar seleccionados'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceLine {
  _InvoiceLine({
    required this.description,
    required this.sku,
    required this.quantity,
    required this.unitCost,
    required this.product,
  });

  final String description;
  final String? sku;
  final int quantity;
  final double unitCost;
  final Product? product;
}

int _asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.round();
  return int.tryParse('$v') ?? fallback;
}

double _asDouble(Object? v) {
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

/// Supplier picker. Watches the live provider (so the list appears as soon as
/// it loads), offers "Proveedor no especificado" (pops '') and quick creation
/// with just a name — extra fiscal data (razón social, CUIT…) is optional.
class _SupplierSheet extends ConsumerStatefulWidget {
  const _SupplierSheet();

  @override
  ConsumerState<_SupplierSheet> createState() => _SupplierSheetState();
}

class _SupplierSheetState extends ConsumerState<_SupplierSheet> {
  bool _busy = false;

  /// Alta con la ventana COMPARTIDA de proveedores/clientes (mismo diseño).
  Future<void> _create() async {
    final data = await PartyFormSheet.show(context, title: 'Nuevo proveedor');
    if (data == null || !mounted) return;
    setState(() => _busy = true);
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    try {
      final created = await ref.read(suppliersRepositoryProvider).create(
            Supplier(
              id: '',
              profileId: userId,
              name: data.name,
              legalName: data.legalName,
              taxId: data.taxId,
              phone: data.phone,
              email: data.email,
            ),
          );
      ref.invalidate(suppliersProvider);
      if (mounted) Navigator.of(context).pop(created.id);
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('No se pudo crear. ${e.toString().split('\n').first}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(suppliersProvider);
    final suppliers = suppliersAsync.valueOrNull ?? const <Supplier>[];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 4),
              const Text('Proveedor',
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
                    Icon(Icons.help_outline,
                        size: 18, color: AppColors.textMuted),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text('Proveedor no especificado',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (suppliersAsync.isLoading && suppliers.isEmpty)
                const Padding(
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
              for (final s in suppliers) ...[
                SurfaceCard(
                  radius: 13,
                  padding: const EdgeInsets.all(12),
                  onTap: () => Navigator.of(context).pop(s.id),
                  child: Row(
                    children: [
                      const Icon(Icons.store_outlined,
                          size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.name,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            if (s.legalName != null || s.taxId != null)
                              Text(
                                [
                                  if (s.legalName != null) s.legalName!,
                                  if (s.taxId != null) s.taxId!,
                                ].join(' · '),
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.add_business_outlined, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.border),
                ),
                label: const Text('Nuevo proveedor'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WarehouseSheet extends StatelessWidget {
  const _WarehouseSheet({required this.warehouses});

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
            const Text('Depósito de la compra',
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
                      color: w.isDefault ? AppColors.primary : AppColors.textSecondary,
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

