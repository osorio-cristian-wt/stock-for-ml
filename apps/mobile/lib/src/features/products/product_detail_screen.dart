import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../price_comparison/price_comparison_screen.dart';
import '../stock_adjustment/stock_adjustment_sheet.dart';
import 'product_form_screen.dart';

/// Screen 05 · Detalle con rentabilidad por unidad. Reactive to the live
/// product stream, so a stock movement updates the numbers immediately.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);
    final economics = ref.watch(economicsByProductProvider)[productId];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
        actions: [
          productsAsync.maybeWhen(
            data: (products) {
              final p = _find(products);
              if (p == null) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductFormScreen(product: p),
                  ),
                ),
                child: const Text('Editar',
                    style: TextStyle(color: AppColors.textSecondary)),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Loading(),
        error: (e, _) => InlineError(
          message: '$e',
          onRetry: () => ref.invalidate(productsStreamProvider),
        ),
        data: (products) {
          final p = _find(products);
          if (p == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Producto no encontrado',
            );
          }
          return _Body(product: p, economics: economics);
        },
      ),
    );
  }

  Product? _find(List<Product> products) {
    for (final p in products) {
      if (p.id == productId) return p;
    }
    return null;
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.product, this.economics});

  final Product product;
  final ProductEconomics? economics;

  @override
  Widget build(BuildContext context) {
    final published = economics != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        _Header(product: product, economics: economics),
        const SizedBox(height: 16),
        if (published)
          _ProfitCard(economics: economics!)
        else
          _InternalCostCard(product: product),
        const SizedBox(height: 12),
        _StockCard(product: product),
        if (published) ...[
          const SizedBox(height: 12),
          SurfaceCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PriceComparisonScreen(
                  listingId: economics!.listingId,
                  mlItemId: economics!.mlItemId,
                  title: product.title,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.insights_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Comparar precios en ML',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product, this.economics});

  final Product product;
  final ProductEconomics? economics;

  @override
  Widget build(BuildContext context) {
    final mlItemId = economics?.mlItemId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductThumb(imageUrl: product.imageUrl, size: 74, radius: 16),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.2)),
              const SizedBox(height: 3),
              Text(
                [
                  if (product.sku != null) product.sku,
                  if (mlItemId != null) mlItemId,
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  economics != null
                      ? TagChip('Activa',
                          color: AppColors.primary,
                          background: AppColors.primarySoft,
                          bold: true)
                      : const TagChip('Interno'),
                  if (product.gtin != null) ...[
                    const SizedBox(width: 6),
                    TagChip('GTIN ${product.gtin}'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.economics});

  final ProductEconomics economics;

  @override
  Widget build(BuildContext context) {
    final e = economics;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rentabilidad por unidad',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const SizedBox(height: 12),
          _Line(label: 'Precio de venta', value: Fmt.ars(e.salePrice)),
          _Line(
            label: 'Comisión ML',
            value: '− ${Fmt.ars(e.estSaleFee)}',
            valueColor: AppColors.danger,
          ),
          _Line(
            label: e.fxRate > 0
                ? 'Costo (${Fmt.usd(e.costInSaleCurrency / e.fxRate)} × ${Fmt.ars(e.fxRate)})'
                : 'Costo',
            value: '− ${Fmt.ars(e.costInSaleCurrency)}',
            valueColor: AppColors.danger,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 11),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ganancia neta',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text(
                Fmt.ars(e.netProfit),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: e.netProfit >= 0 ? AppColors.primary : AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _MiniStat(label: 'Markup', value: Fmt.pct(e.markupPct)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Margen',
                  value: Fmt.pct(e.marginPct),
                  valueColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InternalCostCard extends StatelessWidget {
  const _InternalCostCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Costo de compra',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const SizedBox(height: 10),
          Text(
            product.purchaseCurrency == 'USD'
                ? Fmt.usd(product.purchaseCost)
                : Fmt.ars(product.purchaseCost),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Producto interno (sin publicación en ML). Vinculá una publicación '
            'para ver comisión, markup y margen reales.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stock actual',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '${product.currentStock} ',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    const TextSpan(
                      text: 'u.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ]),
                ),
                if (product.lowStockThreshold != null)
                  Text('umbral: ${product.lowStockThreshold} u.',
                      style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          FilledButton(
            onPressed: () => StockAdjustmentSheet.show(context, product: product),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Ajustar stock'),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.textBody)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
