import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/price_comparison_repository.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';

/// Per-listing comparison request (keeps the FutureProvider cache keyed).
class CompareArgs {
  const CompareArgs(this.listingId, this.mlItemId);
  final String listingId;
  final String? mlItemId;

  @override
  bool operator ==(Object other) =>
      other is CompareArgs &&
      other.listingId == listingId &&
      other.mlItemId == mlItemId;

  @override
  int get hashCode => Object.hash(listingId, mlItemId);
}

final priceComparisonProvider =
    FutureProvider.family<PriceComparison, CompareArgs>((ref, args) {
  return ref.read(priceComparisonRepositoryProvider).compare(
        listingId: args.listingId,
        mlItemId: args.mlItemId,
      );
});

/// Screen 10 · Comparativa de precios dentro de ML (must-have del MVP). Your
/// listing vs. the competition, cheapest first.
class PriceComparisonScreen extends ConsumerWidget {
  const PriceComparisonScreen({
    super.key,
    required this.listingId,
    required this.title,
    this.mlItemId,
  });

  final String listingId;
  final String? mlItemId;
  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final args = CompareArgs(listingId, mlItemId);
    final async = ref.watch(priceComparisonProvider(args));

    return Scaffold(
      appBar: AppBar(title: const Text('Precios en ML')),
      body: async.when(
        loading: () => const Loading(),
        error: (e, _) => InlineError(
          message: 'La comparativa todavía no está disponible. ($e)',
          onRetry: () => ref.invalidate(priceComparisonProvider(args)),
        ),
        data: (cmp) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            Text(
              '${cmp.title.isEmpty ? title : cmp.title}'
              '${cmp.categoryId != null ? " · categoría ${cmp.categoryId}" : ""}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            _YourCard(cmp: cmp),
            const SizedBox(height: 14),
            const _Divider(label: 'competencia'),
            const SizedBox(height: 14),
            if (cmp.competitors.isEmpty)
              const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'Sin competencia detectada',
                message: 'No encontramos otras publicaciones para comparar.',
              )
            else
              for (final c in cmp.competitors) ...[
                _CompetitorRow(competitor: c, yourPrice: cmp.yourPrice),
                const SizedBox(height: 9),
              ],
          ],
        ),
      ),
    );
  }
}

class _YourCard extends StatelessWidget {
  const _YourCard({required this.cmp});

  final PriceComparison cmp;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: 16,
      borderColor: cmp.youAreCheapest ? AppColors.primary : AppColors.border,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('VOS',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.onPrimary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tu publicación',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text('${cmp.yourStock} u · ${cmp.yourSold} vendidos',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Text(Fmt.ars(cmp.yourPrice),
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _CompetitorRow extends StatelessWidget {
  const _CompetitorRow({required this.competitor, required this.yourPrice});

  final CompetitorPrice competitor;
  final double yourPrice;

  @override
  Widget build(BuildContext context) {
    final c = competitor;
    final diff = c.diffPct ??
        (yourPrice > 0 ? (c.price - yourPrice) / yourPrice * 100 : null);
    final cheaper = diff != null && diff < 0;
    final meta = <String>[
      if (c.reputation != null) '★ ${c.reputation!.toStringAsFixed(1)}',
      if (c.isFull) 'Full',
      if (cheaper) 'más barato',
    ].join(' · ');

    return SurfaceCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta,
                      style: TextStyle(
                          fontSize: 11,
                          color: cheaper ? AppColors.primary : AppColors.textMuted)),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.ars(c.price),
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cheaper ? AppColors.primary : AppColors.textPrimary)),
              if (diff != null)
                Text('${diff >= 0 ? "+" : ""}${diff.round()}%',
                    style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
        const Expanded(child: Divider(color: AppColors.border)),
      ],
    );
  }
}
