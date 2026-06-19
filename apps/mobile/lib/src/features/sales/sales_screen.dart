import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';

/// Screen 08 · Ventas. Monthly summary + sales grouped by day (Hoy / Ayer / …).
class SalesScreen extends ConsumerWidget {
  const SalesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync = ref.watch(salesProvider);
    final productList =
        ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final products = {for (final p in productList) p.id: p};

    return Scaffold(
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
            data: (sales) => _SalesList(sales: sales, products: products),
          ),
        ),
      ),
    );
  }
}

double _net(Sale s) => s.netAmount ?? (s.gross - s.saleFee - s.shippingCost);

class _SalesList extends StatelessWidget {
  const _SalesList({required this.sales, required this.products});

  final List<Sale> sales;
  final Map<String, Product> products;

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
              _SaleRow(sale: s, product: products[s.productId]),
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
  const _SaleRow({required this.sale, this.product});

  final Sale sale;
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final title = product?.title ?? sale.mlItemId ?? 'Venta';
    final net = _net(sale);
    return SurfaceCard(
      radius: 15,
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          ProductThumb(imageUrl: product?.imageUrl, size: 40, radius: 11),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                Text(
                  '#${sale.mlOrderId} · ${sale.quantity} u · ${Fmt.clock(sale.soldAt)}',
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
        ],
      ),
    );
  }
}
