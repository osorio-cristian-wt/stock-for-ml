import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../theme/app_colors.dart';
import '../../ui/widgets/app_widgets.dart';
import '../scan/scan_screen.dart';
import 'product_comparison_screen.dart';
import 'product_detail_screen.dart';
import 'product_form_screen.dart';
import 'product_tile.dart';

enum _Filter { all, published, internal }

/// Screen 04 · Productos. Live list with search, publication filter and a
/// barcode-first "+" entry point (scan or manual).
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;
  String _query = '';
  String? _categoryFilter; // category id; null = all categories

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _openProduct(Product p) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: p.id)),
    );
  }

  /// Pull-to-refresh: re-subscribes the live products stream and refetches the
  /// FutureProvider-backed economics/categories (which don't stream).
  Future<void> _refresh() async {
    ref.invalidate(economicsProvider);
    ref.invalidate(categoriesProvider);
    ref.invalidate(productsStreamProvider);
    await ref.read(economicsProvider.future);
  }

  Future<void> _openAdd() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => const _AddSheet(),
    );
    if (!mounted || action == null) return;
    if (action == 'scan') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ScanScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProductFormScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final economics = ref.watch(economicsByProductProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Productos',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProductComparisonScreen(),
                      ),
                    ),
                    tooltip: 'Comparativa',
                    icon: const Icon(Icons.leaderboard_outlined,
                        color: AppColors.textSecondary, size: 22),
                  ),
                  const SizedBox(width: 4),
                  _AddButton(onTap: _openAdd),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'Buscar por título, SKU o marca…',
                  prefixIcon: Icon(Icons.search, color: AppColors.textFaint, size: 20),
                ),
              ),
            ),
            const SizedBox(height: 12),
            productsAsync.when(
              loading: () => const Expanded(child: Loading()),
              error: (e, _) => Expanded(
                child: InlineError(
                  message: '$e',
                  onRetry: () => ref.invalidate(productsStreamProvider),
                ),
              ),
              data: (products) {
                final filtered = _apply(products, economics);
                return Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _FilterRow(
                        filter: _filter,
                        total: products.length,
                        onChanged: (f) => setState(() => _filter = f),
                      ),
                      if (categories.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _CategoryFilterRow(
                          categories: categories,
                          selectedId: _categoryFilter,
                          onChanged: (id) => setState(() => _categoryFilter = id),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Expanded(
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          onRefresh: _refresh,
                          child: filtered.isEmpty
                              ? ListView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  children: [
                                    const SizedBox(height: 80),
                                    EmptyState(
                                      icon: Icons.inventory_2_outlined,
                                      title: products.isEmpty
                                          ? 'Todavía no hay productos'
                                          : 'Sin resultados',
                                      message: products.isEmpty
                                          ? 'Escaneá un código o cargá tu primer producto.'
                                          : 'Probá con otro término o filtro.',
                                      action: products.isEmpty
                                          ? FilledButton.icon(
                                              onPressed: _openAdd,
                                              icon: const Icon(Icons.add),
                                              label: const Text('Agregar producto'),
                                            )
                                          : null,
                                    ),
                                  ],
                                )
                              : ListView.separated(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (_, i) {
                                    final p = filtered[i];
                                    return ProductTile(
                                      product: p,
                                      economics: economics[p.id],
                                      published: economics.containsKey(p.id),
                                      onTap: () => _openProduct(p),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  List<Product> _apply(
    List<Product> products,
    Map<String, ProductEconomics> economics,
  ) {
    return products.where((p) {
      final published = economics.containsKey(p.id);
      switch (_filter) {
        case _Filter.published:
          if (!published) return false;
        case _Filter.internal:
          if (published) return false;
        case _Filter.all:
          break;
      }
      if (_categoryFilter != null && p.categoryId != _categoryFilter) {
        return false;
      }
      if (_query.isEmpty) return true;
      return p.title.toLowerCase().contains(_query) ||
          (p.sku?.toLowerCase().contains(_query) ?? false) ||
          (p.brand?.toLowerCase().contains(_query) ?? false);
    }).toList();
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.filter,
    required this.total,
    required this.onChanged,
  });

  final _Filter filter;
  final int total;
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
            label: 'Todos · $total',
            selected: filter == _Filter.all,
            onTap: () => onChanged(_Filter.all),
          ),
          const SizedBox(width: 7),
          _Chip(
            label: 'Publicados',
            selected: filter == _Filter.published,
            onTap: () => onChanged(_Filter.published),
          ),
          const SizedBox(width: 7),
          _Chip(
            label: 'Internos',
            selected: filter == _Filter.internal,
            onTap: () => onChanged(_Filter.internal),
          ),
        ],
      ),
    );
  }
}

/// Horizontal chip row that filters the list by the user's internal categories.
class _CategoryFilterRow extends StatelessWidget {
  const _CategoryFilterRow({
    required this.categories,
    required this.selectedId,
    required this.onChanged,
  });

  final List<ProductCategory> categories;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _Chip(
            label: 'Todas',
            selected: selectedId == null,
            onTap: () => onChanged(null),
          ),
          for (final c in categories) ...[
            const SizedBox(width: 7),
            _Chip(
              label: c.name,
              selected: selectedId == c.id,
              onTap: () => onChanged(c.id),
            ),
          ],
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

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: const SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.add, color: AppColors.onPrimary, size: 22),
        ),
      ),
    );
  }
}

class _AddSheet extends StatelessWidget {
  const _AddSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            _Option(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Escanear código',
              subtitle: 'EAN/UPC o SKU — lo más rápido',
              highlight: true,
              onTap: () => Navigator.of(context).pop('scan'),
            ),
            const SizedBox(height: 10),
            _Option(
              icon: Icons.edit_note_rounded,
              title: 'Carga manual',
              subtitle: 'Completá los datos a mano',
              onTap: () => Navigator.of(context).pop('manual'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      color: highlight ? AppColors.primarySoft : AppColors.surface,
      borderColor: highlight ? AppColors.primary : AppColors.border,
      child: Row(
        children: [
          Icon(icon, color: highlight ? AppColors.primary : AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textFaint),
        ],
      ),
    );
  }
}
