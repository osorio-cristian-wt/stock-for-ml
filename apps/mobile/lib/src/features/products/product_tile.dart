import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';

/// A product row used in the Productos list. Shows publication state, a stock
/// chip (colored by low-stock severity) and the listing margin.
class ProductTile extends StatelessWidget {
  const ProductTile({
    super.key,
    required this.product,
    this.economics,
    this.published = false,
    this.onTap,
  });

  final Product product;
  final ProductEconomics? economics;
  final bool published;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final margin = economics?.marginPct;
    final priceLabel = economics != null
        ? Fmt.ars(economics!.salePrice)
        : (product.sku ?? 'sin publicar');

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(11),
      radius: 16,
      child: Row(
        children: [
          ProductThumb(imageUrl: product.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  economics != null && product.sku != null
                      ? '${product.sku} · $priceLabel'
                      : priceLabel,
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    published
                        ? TagChip('Publicado',
                            color: AppColors.primary,
                            background: AppColors.primarySoft,
                            bold: true)
                        : const TagChip('Interno'),
                    const SizedBox(width: 6),
                    _StockChip(product: product),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('margen',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
              Text(
                Fmt.pct(margin),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: margin == null ? AppColors.textSecondary : AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Stock count chip whose color encodes severity (ok / low / out).
class _StockChip extends StatelessWidget {
  const _StockChip({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final qty = product.currentStock;
    if (qty <= 0) {
      return TagChip('0 u. · sin stock',
          color: AppColors.danger, background: AppColors.dangerSoft, bold: true);
    }
    if (product.isLowStock) {
      final critical = product.lowStockThreshold != null &&
          qty <= (product.lowStockThreshold! / 2).ceil();
      return TagChip(
        '${product.currentStock} u. · bajo',
        color: critical ? AppColors.danger : AppColors.warning,
        background: critical ? AppColors.dangerSoft : AppColors.warningSoft,
        bold: true,
      );
    }
    return TagChip('${product.currentStock} u.', color: AppColors.textSecondary);
  }
}
