import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/widgets/app_widgets.dart';

/// Gestión de las categorías internas del usuario (Ajustes → Categorías):
/// crear, renombrar (lápiz) y eliminar. Al eliminar, los productos que la
/// usaban quedan "sin categoría" — nunca se pierde un producto.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  String _slugify(String s) => s
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');

  Future<String?> _promptName({String? initial, required String title}) {
    final controller = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Ej. Auriculares'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final name = await _promptName(title: 'Nueva categoría');
    if (name == null || name.isEmpty || !mounted) return;
    final slug = _slugify(name);
    if (slug.isEmpty) return;
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    try {
      await ref.read(inventoryRepositoryProvider).createCategory(
            ProductCategory(id: '', profileId: userId, name: name, slug: slug),
          );
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (mounted) showAppError(context, e, title: 'No se pudo crear la categoría');
    }
  }

  Future<void> _rename(ProductCategory c) async {
    final name = await _promptName(initial: c.name, title: 'Renombrar categoría');
    if (name == null || name.isEmpty || name == c.name || !mounted) return;
    final slug = _slugify(name);
    if (slug.isEmpty) return;
    try {
      await ref.read(inventoryRepositoryProvider).renameCategory(c.id, name, slug);
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (mounted) {
        showAppError(context, e, title: 'No se pudo renombrar la categoría');
      }
    }
  }

  Future<void> _delete(ProductCategory c, int productCount) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('Eliminar "${c.name}"',
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: Text(
          productCount > 0
              ? '$productCount producto${productCount == 1 ? '' : 's'} '
                  'quedará${productCount == 1 ? '' : 'n'} sin categoría '
                  '(no se borra ningún producto).'
              : 'La categoría no tiene productos asignados.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger, minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(inventoryRepositoryProvider).deleteCategory(c.id);
      ref.invalidate(categoriesProvider);
      ref.invalidate(productsStreamProvider);
    } catch (e) {
      if (mounted) {
        showAppError(context, e, title: 'No se pudo eliminar la categoría');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    final products =
        ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final countByCategory = <String, int>{};
    for (final p in products) {
      final id = p.categoryId;
      if (id != null) countByCategory[id] = (countByCategory[id] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Categorías')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('Nueva'),
      ),
      body: SafeArea(
        child: categoriesAsync.when(
          loading: () => const Loading(),
          error: (e, _) => InlineError(
            message: AppErrors.friendly(e),
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
          data: (categories) => categories.isEmpty
              ? const EmptyState(
                  icon: Icons.category_outlined,
                  title: 'Sin categorías',
                  message:
                      'Creá categorías para agrupar y filtrar tus productos.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 9),
                  itemBuilder: (_, i) {
                    final c = categories[i];
                    final count = countByCategory[c.id] ?? 0;
                    return SurfaceCard(
                      radius: 14,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.category_outlined,
                              size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                                Text(
                                  '$count producto${count == 1 ? '' : 's'}',
                                  style: const TextStyle(
                                      fontSize: 11, color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Renombrar',
                            icon: const Icon(Icons.edit_outlined,
                                size: 18, color: AppColors.textMuted),
                            onPressed: () => _rename(c),
                          ),
                          IconButton(
                            tooltip: 'Eliminar',
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: AppColors.danger),
                            onPressed: () => _delete(c, count),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
