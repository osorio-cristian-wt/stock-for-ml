import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/economics_repository.dart';
import '../../data/queries.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../products/product_detail_screen.dart';

enum _Period { d7, d30, d90, month, all }

enum _Channel { all, ml, local }

/// RF-44 · Tab "Stats": ganancia REAL por período (v_sale_profit) con filtros
/// de rango, canal y categoría, más top de productos. Consistente con RF-40:
/// las ventas con productos sin costo NO suman ganancia — se cuentan aparte
/// como "sin costear".
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  _Period _period = _Period.d30;
  _Channel _channel = _Channel.all;
  String? _categoryId;

  DateTime? get _cutoff {
    final now = DateTime.now();
    return switch (_period) {
      _Period.d7 => now.subtract(const Duration(days: 7)),
      _Period.d30 => now.subtract(const Duration(days: 30)),
      _Period.d90 => now.subtract(const Duration(days: 90)),
      _Period.month => DateTime(now.year, now.month, 1),
      _Period.all => null,
    };
  }

  List<Sale> _filtered(
    List<Sale> sales,
    Map<String, Product> products,
  ) {
    final cutoff = _cutoff;
    return [
      for (final s in sales)
        if (s.status != 'cancelled')
          if (cutoff == null || (s.soldAt?.isAfter(cutoff) ?? false))
            if (_channel == _Channel.all ||
                (_channel == _Channel.ml
                    ? s.channel == SaleChannel.ml
                    : s.channel == SaleChannel.local))
              if (_categoryId == null ||
                  products[s.productId]?.categoryId == _categoryId)
                s,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final salesAsync = ref.watch(salesProvider);
    final profits =
        ref.watch(saleProfitsProvider).valueOrNull ?? const <String, SaleProfit>{};
    final products = {
      for (final p
          in ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[])
        p.id: p,
    };
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: salesAsync.when(
          loading: () => const Loading(),
          error: (e, _) => InlineError(
            message: '$e',
            onRetry: () => ref.invalidate(salesProvider),
          ),
          data: (sales) {
            final rows = _filtered(sales, products);
            double gross = 0, net = 0;
            int units = 0, uncosted = 0;
            final unitsByProduct = <String, int>{};
            final profitByProduct = <String, double>{};
            for (final s in rows) {
              gross += s.gross;
              units += s.quantity;
              final p = profits[s.id];
              if (p == null || !p.hasFullCost) {
                uncosted++;
              } else {
                net += p.netProfit ?? 0;
              }
              final pid = s.productId;
              if (pid != null) {
                unitsByProduct[pid] = (unitsByProduct[pid] ?? 0) + s.quantity;
                final np = p?.netProfit;
                if (np != null) {
                  profitByProduct[pid] = (profitByProduct[pid] ?? 0) + np;
                }
              }
            }
            final top = unitsByProduct.entries.toList()
              ..sort((a, b) => b.value.compareTo(a.value));

            return RefreshIndicator(
              color: AppColors.primary,
              backgroundColor: AppColors.surface,
              onRefresh: () async {
                ref.invalidate(salesProvider);
                ref.invalidate(saleProfitsProvider);
                await ref.read(salesProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                children: [
                  const Text('Estadísticas',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 14),
                  _ChipRow(children: [
                    for (final p in _Period.values)
                      _FilterChip(
                        label: switch (p) {
                          _Period.d7 => '7 días',
                          _Period.d30 => '30 días',
                          _Period.d90 => '90 días',
                          _Period.month => 'Este mes',
                          _Period.all => 'Todo',
                        },
                        selected: _period == p,
                        onTap: () => setState(() => _period = p),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  _ChipRow(children: [
                    for (final c in _Channel.values)
                      _FilterChip(
                        label: switch (c) {
                          _Channel.all => 'Todos los canales',
                          _Channel.ml => 'MercadoLibre',
                          _Channel.local => 'Venta local',
                        },
                        selected: _channel == c,
                        onTap: () => setState(() => _channel = c),
                      ),
                  ]),
                  if (categories.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ChipRow(children: [
                      _FilterChip(
                        label: 'Todas las categorías',
                        selected: _categoryId == null,
                        onTap: () => setState(() => _categoryId = null),
                      ),
                      for (final c in categories)
                        _FilterChip(
                          label: c.name,
                          selected: _categoryId == c.id,
                          onTap: () => setState(() => _categoryId = c.id),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _KpiCard(
                            label: 'Facturado',
                            value: Fmt.ars(gross),
                            sub: '${rows.length} venta${rows.length == 1 ? '' : 's'} · $units u.'),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _KpiCard(
                          label: 'Ganancia real',
                          value: Fmt.arsSigned(net),
                          valueColor:
                              net >= 0 ? AppColors.primary : AppColors.danger,
                          sub: uncosted > 0
                              ? '$uncosted sin costear (no suman)'
                              : 'comisión, envío e impuestos descontados',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const SectionHeader('Top productos del período', uppercase: true),
                  const SizedBox(height: 10),
                  if (top.isEmpty)
                    const SurfaceCard(
                      child: Text('Sin ventas en el período elegido.',
                          style:
                              TextStyle(fontSize: 13, color: AppColors.textMuted)),
                    )
                  else
                    for (final entry in top.take(8)) ...[
                      _TopProductTile(
                        product: products[entry.key],
                        units: entry.value,
                        profit: profitByProduct[entry.key],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                ProductDetailScreen(productId: entry.key),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color:
                    selected ? AppColors.onPrimary : AppColors.textSecondary)),
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  final String label;
  final String value;
  final String sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(sub,
              style: const TextStyle(fontSize: 10.5, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

class _TopProductTile extends StatelessWidget {
  const _TopProductTile({
    required this.product,
    required this.units,
    required this.profit,
    required this.onTap,
  });

  final Product? product;
  final int units;
  final double? profit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        children: [
          ProductThumb(imageUrl: product?.imageUrl, size: 40, radius: 10),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product?.title ?? 'Producto',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text('$units unidad${units == 1 ? '' : 'es'}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(
            profit == null ? 'sin costear' : Fmt.arsSigned(profit!),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: profit == null
                  ? AppColors.textMuted
                  : profit! >= 0
                      ? AppColors.primary
                      : AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
