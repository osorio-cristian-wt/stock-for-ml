import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/economics_repository.dart';
import '../../data/local/app_db.dart';
import '../../data/pending_ops_repository.dart';
import '../../data/pending_ops_service.dart';
import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../purchases/purchase_edit_screen.dart';
import '../sales/local_sale_screen.dart';
import 'pending_ops_section.dart';
import 'transfer_screen.dart';

/// Tab Movimientos · feed unificado de ventas + compras + transferencias,
/// agrupado por día (Hoy / Ayer / dd-mm) con chips de filtro y un speed dial
/// con las tres acciones: Nueva venta · Nueva compra · Transferir.
class MovementsScreen extends ConsumerStatefulWidget {
  const MovementsScreen({super.key});

  @override
  ConsumerState<MovementsScreen> createState() => _MovementsScreenState();
}

enum _Filter { all, sales, purchases, transfers }

class _MovementsScreenState extends ConsumerState<MovementsScreen> {
  _Filter _filter = _Filter.all;
  bool _dialOpen = false;

  void _closeDial() => setState(() => _dialOpen = false);

  /// La compra arranca EN MEMORIA: el borrador recién se persiste cuando se
  /// carga el primer producto (estándar de borradores del feed).
  void _newPurchase() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PurchaseEditScreen()),
    );
  }

  /// Borra (cancela) todos los borradores de compra pendientes.
  Future<void> _clearDrafts(List<Purchase> drafts) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Limpiar borradores',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Se descartan ${drafts.length} borrador${drafts.length == 1 ? '' : 'es'} '
          'de compra (sus líneas no impactaron el stock).',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Limpiar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final repo = ref.read(purchasesRepositoryProvider);
      for (final d in drafts) {
        await repo.cancel(d.id);
      }
    } catch (e) {
      if (mounted) {
        showAppError(context, e, title: 'No se pudieron limpiar los borradores');
      }
    }
  }

  bool _matches(MovementEntry e) => switch (_filter) {
        _Filter.all => true,
        _Filter.sales => e is SaleEntry,
        _Filter.purchases => e is PurchaseEntry,
        _Filter.transfers => e is TransferEntry,
      };

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesProvider);
    final purchasesAsync = ref.watch(purchasesStreamProvider);
    final transfersAsync = ref.watch(transfersStreamProvider);
    final feed = ref.watch(movementsFeedProvider);
    // Los borradores viven en su propia sección arriba del feed. Una compra
    // cuyo cierre está encolado offline ya no es editable como borrador: se
    // muestra solo en "Pendientes de subir".
    final pendingOps =
        ref.watch(pendingOpsProvider).valueOrNull ?? const <PendingOp>[];
    final pendingCloseIds = {
      for (final op in pendingOps)
        if (op.kind == PendingOpKind.purchaseClose) op.id,
    };
    final drafts = [
      for (final p in purchasesAsync.valueOrNull ?? const <Purchase>[])
        if (p.isDraft && !pendingCloseIds.contains(p.id)) p,
    ];
    final entries = feed
        .where(_matches)
        .where((e) => !(e is PurchaseEntry && e.purchase.isDraft))
        .toList();

    final products = {
      for (final p
          in ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[])
        p.id: p,
    };
    final customers = {
      for (final c
          in ref.watch(customersProvider).valueOrNull ?? const <Customer>[])
        c.id: c,
    };
    final suppliers = {
      for (final s
          in ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[])
        s.id: s,
    };
    final warehouseNames = {
      for (final w
          in ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[])
        w.id: w.name,
    };

    final booting = feed.isEmpty &&
        (salesAsync.isLoading ||
            purchasesAsync.isLoading ||
            transfersAsync.isLoading);
    final sales = salesAsync.valueOrNull ?? const <Sale>[];

    return Scaffold(
      floatingActionButton: _SpeedDial(
        open: _dialOpen,
        onToggle: () => setState(() => _dialOpen = !_dialOpen),
        onSale: () {
          _closeDial();
          LocalSaleScreen.open(context);
        },
        onPurchase: () {
          _closeDial();
          _newPurchase();
        },
        onTransfer: () {
          _closeDial();
          TransferScreen.open(context);
        },
      ),
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 14, 20, 12),
                  child: Text('Movimientos',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                _FilterRow(
                  filter: _filter,
                  onChanged: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: booting
                      ? const Loading()
                      : RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          onRefresh: () async {
                            ref.invalidate(salesProvider);
                            await ref.read(salesProvider.future);
                          },
                          child: _FeedList(
                            filter: _filter,
                            entries: entries,
                            drafts: drafts,
                            onClearDrafts: () => _clearDrafts(drafts),
                            sales: sales,
                            salesError: salesAsync.hasError
                                ? '${salesAsync.error}'
                                : null,
                            onRetrySales: () => ref.invalidate(salesProvider),
                            products: products,
                            customers: customers,
                            suppliers: suppliers,
                            warehouseNames: warehouseNames,
                          ),
                        ),
                ),
              ],
            ),
          ),
          if (_dialOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeDial,
                child: Container(color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

double _net(Sale s) => s.netAmount ?? (s.gross - s.saleFee - s.shippingCost);

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.filter, required this.onChanged});

  final _Filter filter;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _Chip(
            label: 'Todos',
            selected: filter == _Filter.all,
            onTap: () => onChanged(_Filter.all),
          ),
          const SizedBox(width: 7),
          _Chip(
            label: 'Ventas',
            selected: filter == _Filter.sales,
            onTap: () => onChanged(_Filter.sales),
          ),
          const SizedBox(width: 7),
          _Chip(
            label: 'Compras',
            selected: filter == _Filter.purchases,
            onTap: () => onChanged(_Filter.purchases),
          ),
          const SizedBox(width: 7),
          _Chip(
            label: 'Transferencias',
            selected: filter == _Filter.transfers,
            onTap: () => onChanged(_Filter.transfers),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? AppColors.onPrimary : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// Cuerpo del feed: resumen del mes (en Todos/Ventas), error de ventas si lo
/// hubo (las compras/transferencias siguen visibles) y las entradas agrupadas
/// por día.
class _FeedList extends StatelessWidget {
  const _FeedList({
    required this.filter,
    required this.entries,
    required this.drafts,
    required this.onClearDrafts,
    required this.sales,
    required this.salesError,
    required this.onRetrySales,
    required this.products,
    required this.customers,
    required this.suppliers,
    required this.warehouseNames,
  });

  final _Filter filter;
  final List<MovementEntry> entries;
  final List<Purchase> drafts;
  final VoidCallback onClearDrafts;
  final List<Sale> sales;
  final String? salesError;
  final VoidCallback onRetrySales;
  final Map<String, Product> products;
  final Map<String, Customer> customers;
  final Map<String, Supplier> suppliers;
  final Map<String, String> warehouseNames;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDay(entries, DateTime.now());
    final showSummary = filter == _Filter.all || filter == _Filter.sales;
    final showDrafts = drafts.isNotEmpty &&
        (filter == _Filter.all || filter == _Filter.purchases);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
      children: [
        if (showSummary) ...[
          _MonthSummaryCard(sales: sales),
          const SizedBox(height: 18),
        ],
        if (salesError != null) ...[
          InlineError(message: salesError!, onRetry: onRetrySales),
          const SizedBox(height: 18),
        ],
        // Operaciones confirmadas sin red, esperando sincronizarse (se oculta
        // sola si la cola está vacía).
        const PendingOpsSection(),
        if (showDrafts) ...[
          SectionHeader('Borradores',
              uppercase: true, actionLabel: 'Limpiar', onAction: onClearDrafts),
          const SizedBox(height: 10),
          for (final d in drafts) ...[
            _PurchaseRow(purchase: d, supplier: suppliers[d.supplierId]),
            const SizedBox(height: 9),
          ],
          const SizedBox(height: 8),
        ],
        if (entries.isEmpty && !showDrafts)
          Padding(
            padding: const EdgeInsets.only(top: 40),
            child: _emptyState(),
          )
        else
          for (final group in groups) ...[
            SectionHeader(group.label, uppercase: true),
            const SizedBox(height: 10),
            for (final e in group.entries) ...[
              _row(e),
              const SizedBox(height: 9),
            ],
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _row(MovementEntry e) => switch (e) {
        SaleEntry(:final sale) => _SaleRow(
            sale: sale,
            product: products[sale.productId],
            customer: sale.customerId == null ? null : customers[sale.customerId],
          ),
        PurchaseEntry(:final purchase) => _PurchaseRow(
            purchase: purchase,
            supplier: suppliers[purchase.supplierId],
          ),
        TransferEntry(:final transfer) => _TransferRow(
            transfer: transfer,
            product: products[transfer.productId],
            warehouseNames: warehouseNames,
          ),
      };

  Widget _emptyState() => switch (filter) {
        _Filter.all => const EmptyState(
            icon: Icons.swap_horiz_rounded,
            title: 'Sin movimientos todavía',
            message: 'Cargá una venta, una compra o una transferencia '
                'con el botón +.',
          ),
        _Filter.sales => const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Todavía no hay ventas',
            message: 'Cuando vendas en ML o cargues una venta local, '
                'las verás acá con su ganancia neta.',
          ),
        _Filter.purchases => const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Todavía no hay compras',
            message: 'Cargá una compra a un proveedor con el botón +.',
          ),
        _Filter.transfers => const EmptyState(
            icon: Icons.swap_horiz_rounded,
            title: 'Sin transferencias',
            message: 'Movés stock entre depósitos con el botón +.',
          ),
      };

  List<_DayGroup> _groupByDay(List<MovementEntry> entries, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final map = <String, _DayGroup>{};
    final order = <String>[];

    String labelFor(DateTime? d) {
      if (d == null) return 'Sin fecha';
      final local = DateTime(d.toLocal().year, d.toLocal().month, d.toLocal().day);
      final diff = today.difference(local).inDays;
      if (diff <= 0) return 'Hoy';
      if (diff == 1) return 'Ayer';
      return '${local.day.toString().padLeft(2, '0')}/'
          '${local.month.toString().padLeft(2, '0')}';
    }

    for (final e in entries) {
      final label = labelFor(e.date);
      final g = map.putIfAbsent(label, () {
        order.add(label);
        return _DayGroup(label);
      });
      g.entries.add(e);
    }
    return order.map((l) => map[l]!).toList();
  }
}

class _DayGroup {
  _DayGroup(this.label);
  final String label;
  final List<MovementEntry> entries = [];
}

/// "Este mes" (bruto) + ganancia REAL (v_sale_profit: descuenta comisión,
/// envío y costo según la política de costeo elegida en Ajustes).
class _MonthSummaryCard extends ConsumerWidget {
  const _MonthSummaryCard({required this.sales});

  final List<Sale> sales;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profits =
        ref.watch(saleProfitsProvider).valueOrNull ?? const <String, SaleProfit>{};
    final now = DateTime.now();
    final monthSales = sales.where((s) {
      final d = s.soldAt?.toLocal();
      return d != null && d.year == now.year && d.month == now.month;
    });
    final monthGross = monthSales.fold<double>(0, (a, s) => a + s.gross);
    // RF-40: ventas de productos sin costo no suman ganancia (netProfit null)
    // en vez de inflar el total con un costo 0.
    final monthNet = monthSales.fold<double>(0, (a, s) {
      final p = profits[s.id];
      if (p != null) return a + (p.netProfit ?? 0);
      return a + _net(s);
    });

    return SurfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Ventas este mes',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(Fmt.ars(monthGross),
                    style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Ganancia',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 2),
              Text(Fmt.ars(monthNet),
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale, this.product, this.customer});

  final Sale sale;
  final Product? product;
  final Customer? customer;

  @override
  Widget build(BuildContext context) {
    final title = product?.title ?? sale.mlItemId ?? 'Venta';
    final net = _net(sale);
    final detail = [
      if (sale.isLocal)
        customer?.name ?? 'Sin cliente'
      else
        '#${sale.mlOrderId ?? '—'}',
      '${sale.quantity} u',
      Fmt.clock(sale.soldAt),
    ].join(' · ');
    return SurfaceCard(
      radius: 15,
      padding: const EdgeInsets.all(11),
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            _SaleDetailSheet(sale: sale, product: product, customer: customer),
      ),
      child: Row(
        children: [
          ProductThumb(imageUrl: product?.imageUrl, size: 40, radius: 11),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    sale.isLocal
                        ? TagChip('Local',
                            color: AppColors.primary,
                            background: AppColors.primarySoft,
                            bold: true)
                        : const TagChip('ML', bold: true),
                  ],
                ),
                Text(
                  detail,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.ars(sale.gross),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text(Fmt.arsSigned(net),
                  style: const TextStyle(fontSize: 11, color: AppColors.primary)),
            ],
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase, this.supplier});

  final Purchase purchase;
  final Supplier? supplier;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final draft = p.isDraft;
    final totalText = p.currency == 'USD' ? Fmt.usd(p.total) : Fmt.ars(p.total);
    return SurfaceCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PurchaseEditScreen(purchase: p)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceDeep,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              draft ? Icons.edit_note_rounded : Icons.inventory_2_outlined,
              color: draft ? AppColors.textSecondary : AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(supplier?.name ?? 'Sin proveedor',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    const TagChip('Compra', bold: true),
                  ],
                ),
                Text(
                  [
                    if (p.reference != null) '#${p.reference}',
                    Fmt.shortDate(p.purchasedAt ?? p.createdAt),
                  ].join(' · '),
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              draft
                  ? const TagChip('Borrador')
                  : TagChip('Cerrada',
                      color: AppColors.primary,
                      background: AppColors.primarySoft,
                      bold: true),
              const SizedBox(height: 4),
              if (!draft || p.total > 0)
                Text(totalText,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Una transferencia colapsada: producto, ruta origen → destino y unidades.
class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.transfer,
    this.product,
    required this.warehouseNames,
  });

  final TransferGroup transfer;
  final Product? product;
  final Map<String, String> warehouseNames;

  @override
  Widget build(BuildContext context) {
    final t = transfer;
    final from = t.fromWarehouseId == null
        ? '—'
        : warehouseNames[t.fromWarehouseId] ?? 'Depósito';
    final to = t.toWarehouseId == null
        ? '—'
        : warehouseNames[t.toWarehouseId] ?? 'Depósito';
    return SurfaceCard(
      radius: 15,
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceDeep,
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.swap_horiz_rounded,
                color: AppColors.textSecondary, size: 20),
          ),
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
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                Text(
                  '$from → $to · ${Fmt.clock(t.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${t.qty} u.',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

/// Detalle de una venta: canal, cliente/orden y las LÍNEAS de producto
/// (`sale_items`, cargadas a demanda — las órdenes ML de varios productos
/// muestran una fila por ítem).
class _SaleDetailSheet extends ConsumerWidget {
  const _SaleDetailSheet({required this.sale, this.product, this.customer});

  final Sale sale;
  final Product? product;
  final Customer? customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final net = _net(sale);
    final profit =
        ref.watch(saleProfitsProvider).valueOrNull?[sale.id];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                sale.isLocal
                    ? TagChip('Venta local',
                        color: AppColors.primary,
                        background: AppColors.primarySoft,
                        bold: true)
                    : const TagChip('Venta ML', bold: true),
                const Spacer(),
                Text(Fmt.shortDate(sale.soldAt),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              sale.isLocal
                  ? (customer?.name ?? 'Sin cliente')
                  : 'Orden #${sale.mlOrderId ?? '—'}',
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<SaleItem>>(
              future: ref.read(salesRepositoryProvider).itemsFor(sale.id),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.primary),
                      ),
                    ),
                  );
                }
                final items = snap.data ?? const <SaleItem>[];
                if (items.isEmpty) {
                  // Ventas anteriores al soporte multi-ítem: resumen simple.
                  return _Line(
                    title: product?.title ?? sale.mlItemId ?? 'Producto',
                    qty: sale.quantity,
                    unitPrice: sale.unitPrice,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final it in items) ...[
                      _Line(
                        title: it.title ?? it.mlItemId ?? 'Producto',
                        qty: it.quantity,
                        unitPrice: it.unitPrice,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: AppColors.border),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
                Text(Fmt.ars(sale.gross),
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
            if (sale.saleFee > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Comisión ML',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    Text('− ${Fmt.ars(sale.saleFee)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.danger)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Neto',
                      style:
                          TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  Text(Fmt.arsSigned(net),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ],
              ),
            ),
            if (profit != null) ...[
              if (profit.costArs != null && profit.costArs! > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Costo de lo vendido',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textMuted)),
                      Text('− ${Fmt.ars(profit.costArs!)}',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.danger)),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ganancia',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary)),
                    Text(
                        profit.netProfit == null
                            ? 'Sin costo cargado'
                            : Fmt.arsSigned(profit.netProfit!),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: profit.netProfit == null
                                ? AppColors.textMuted
                                : profit.netProfit! >= 0
                                    ? AppColors.primary
                                    : AppColors.danger)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.title, required this.qty, required this.unitPrice});

  final String title;
  final int qty;
  final double unitPrice;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
        ),
        const SizedBox(width: 8),
        Text('$qty × ${Fmt.ars(unitPrice)}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(width: 10),
        Text(Fmt.ars(qty * unitPrice),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

/// FAB "+" que despliega las tres acciones etiquetadas (speed dial). La más
/// usada (Nueva venta) queda más cerca del botón principal.
class _SpeedDial extends StatelessWidget {
  const _SpeedDial({
    required this.open,
    required this.onToggle,
    required this.onSale,
    required this.onPurchase,
    required this.onTransfer,
  });

  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onSale;
  final VoidCallback onPurchase;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (open) ...[
          _DialAction(
            icon: Icons.swap_horiz_rounded,
            label: 'Transferir',
            onTap: onTransfer,
          ),
          const SizedBox(height: 10),
          _DialAction(
            icon: Icons.receipt_long_rounded,
            label: 'Nueva compra',
            onTap: onPurchase,
          ),
          const SizedBox(height: 10),
          _DialAction(
            icon: Icons.point_of_sale_rounded,
            label: 'Nueva venta',
            onTap: onSale,
          ),
          const SizedBox(height: 14),
        ],
        FloatingActionButton(
          onPressed: onToggle,
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          child: AnimatedRotation(
            turns: open ? 0.125 : 0,
            duration: const Duration(milliseconds: 150),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

class _DialAction extends StatelessWidget {
  const _DialAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
          const SizedBox(width: 10),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.borderStrong),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
