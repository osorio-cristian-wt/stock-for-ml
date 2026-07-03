import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import 'local_sale_screen.dart';

/// Screen 08 · Ventas. Monthly summary + sales grouped by day (Hoy / Ayer / …),
/// with the "Nueva venta" entry point (local multi-item sale, same flow as a
/// purchase). Tapping a sale opens its detail with the product lines.
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesProvider);
    final productList =
        ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final products = {for (final p in productList) p.id: p};
    final customers = {
      for (final c
          in ref.watch(customersProvider).valueOrNull ?? const <Customer>[])
        c.id: c,
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => LocalSaleScreen.open(context),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.point_of_sale_rounded),
        label: const Text('Nueva venta'),
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(salesProvider);
            await ref.read(salesProvider.future);
          },
          child: salesAsync.when(
            loading: () => const Loading(),
            error: (e, _) => ListView(children: [
              const SizedBox(height: 60),
              InlineError(message: '$e', onRetry: () => ref.invalidate(salesProvider)),
            ]),
            data: (sales) => _SalesList(
                sales: sales, products: products, customers: customers),
          ),
        ),
      ),
    );
  }
}

double _net(Sale s) => s.netAmount ?? (s.gross - s.saleFee - s.shippingCost);

class _SalesList extends StatelessWidget {
  const _SalesList({
    required this.sales,
    required this.products,
    required this.customers,
  });

  final List<Sale> sales;
  final Map<String, Product> products;
  final Map<String, Customer> customers;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthSales = sales.where((s) {
      final d = s.soldAt?.toLocal();
      return d != null && d.year == now.year && d.month == now.month;
    });
    final monthGross = monthSales.fold<double>(0, (a, s) => a + s.gross);
    final monthNet = monthSales.fold<double>(0, (a, s) => a + _net(s));

    final groups = _groupByDay(sales, now);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      children: [
        const Text('Ventas',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Este mes',
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
        ),
        const SizedBox(height: 18),
        if (sales.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 40),
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'Todavía no hay ventas',
              message: 'Cuando vendas en ML, las verás acá con su ganancia neta.',
            ),
          )
        else
          for (final group in groups) ...[
            SectionHeader(group.label, uppercase: true),
            const SizedBox(height: 10),
            for (final s in group.sales) ...[
              _SaleRow(
                sale: s,
                product: products[s.productId],
                customer:
                    s.customerId == null ? null : customers[s.customerId],
              ),
              const SizedBox(height: 9),
            ],
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  List<_DayGroup> _groupByDay(List<Sale> sales, DateTime now) {
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

    for (final s in sales) {
      final label = labelFor(s.soldAt);
      final g = map.putIfAbsent(label, () {
        order.add(label);
        return _DayGroup(label);
      });
      g.sales.add(s);
    }
    return order.map((l) => map[l]!).toList();
  }
}

class _DayGroup {
  _DayGroup(this.label);
  final String label;
  final List<Sale> sales = [];
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
