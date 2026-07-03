import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import 'product_detail_screen.dart';

enum _SortBy { margin, markup, profit, rotation }

/// RF-19 · Comparativa entre productos propios: rentabilidad (ganancia neta),
/// margen, markup y rotación (unidades vendidas en los últimos 30 días).
/// Los productos sin publicación quedan al final (no tienen economics).
class ProductComparisonScreen extends ConsumerStatefulWidget {
  const ProductComparisonScreen({super.key});

  @override
  ConsumerState<ProductComparisonScreen> createState() =>
      _ProductComparisonScreenState();
}

class _ProductComparisonScreenState
    extends ConsumerState<ProductComparisonScreen> {
  _SortBy _sortBy = _SortBy.margin;

  double? _metric(ProductComparisonRow r) => switch (_sortBy) {
        _SortBy.margin => r.marginPct,
        _SortBy.markup => r.markupPct,
        _SortBy.profit => r.netProfit,
        _SortBy.rotation => r.soldUnits30d.toDouble(),
      };

  String _metricText(ProductComparisonRow r) {
    final v = _metric(r);
    if (v == null) return '—';
    return switch (_sortBy) {
      _SortBy.margin || _SortBy.markup => Fmt.pct(v),
      _SortBy.profit => Fmt.ars(v),
      _SortBy.rotation => '${r.soldUnits30d} u.',
    };
  }

  List<ProductComparisonRow> _sorted(List<ProductComparisonRow> rows) {
    final sorted = [...rows];
    // Nulls (internal products without economics) always sink to the bottom.
    sorted.sort((a, b) {
      final ma = _metric(a);
      final mb = _metric(b);
      if (ma == null && mb == null) return a.title.compareTo(b.title);
      if (ma == null) return 1;
      if (mb == null) return -1;
      return mb.compareTo(ma);
    });
    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final rowsAsync = ref.watch(productComparisonProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Comparativa')),
      body: rowsAsync.when(
        loading: () => const Loading(),
        error: (e, _) => InlineError(
          message: '$e',
          onRetry: () => ref.invalidate(productComparisonProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.leaderboard_outlined,
              title: 'Nada para comparar',
              message: 'Cargá productos para ver su rentabilidad y rotación.',
            );
          }
          final sorted = _sorted(rows);
          return RefreshIndicator(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            onRefresh: () async {
              ref.invalidate(economicsProvider);
              ref.invalidate(productComparisonProvider);
              await ref.read(productComparisonProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                SizedBox(
                  height: 32,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final s in _SortBy.values) ...[
                        _SortChip(
                          label: switch (s) {
                            _SortBy.margin => 'Margen',
                            _SortBy.markup => 'Markup',
                            _SortBy.profit => 'Ganancia',
                            _SortBy.rotation => 'Rotación 30d',
                          },
                          selected: _sortBy == s,
                          onTap: () => setState(() => _sortBy = s),
                        ),
                        const SizedBox(width: 7),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                for (var i = 0; i < sorted.length; i++) ...[
                  _ComparisonTile(
                    rank: i + 1,
                    row: sorted[i],
                    metricText: _metricText(sorted[i]),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ProductDetailScreen(productId: sorted[i].productId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
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

class _ComparisonTile extends StatelessWidget {
  const _ComparisonTile({
    required this.rank,
    required this.row,
    required this.metricText,
    required this.onTap,
  });

  final int rank;
  final ProductComparisonRow row;
  final String metricText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: rank <= 3 ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ),
          ProductThumb(imageUrl: row.imageUrl, size: 42, radius: 10),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(
                  '${row.soldUnits30d} vend. 30d · stock ${row.currentStock}'
                  '${row.published ? '' : ' · interno'}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            metricText,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}
