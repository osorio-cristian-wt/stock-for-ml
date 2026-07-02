import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import 'purchase_edit_screen.dart';

/// Compras tab · history of supplier purchases + entry point to load a new one.
class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  Future<void> _newPurchase(BuildContext context, WidgetRef ref) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    try {
      final draft =
          await ref.read(purchasesRepositoryProvider).createDraft(profileId: userId);
      if (!context.mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PurchaseEditScreen(purchase: draft)),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo crear la compra. $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchasesAsync = ref.watch(purchasesStreamProvider);
    final suppliers = {
      for (final s in ref.watch(suppliersProvider).valueOrNull ?? const <Supplier>[])
        s.id: s,
    };

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newPurchase(context, ref),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        icon: const Icon(Icons.add),
        label: const Text('Nueva compra'),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text('Compras',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            Expanded(
              child: purchasesAsync.when(
                loading: () => const Loading(),
                error: (e, _) => InlineError(
                  message: '$e',
                  onRetry: () => ref.invalidate(purchasesStreamProvider),
                ),
                data: (purchases) {
                  final visible = purchases
                      .where((p) => p.status != PurchaseStatus.cancelled)
                      .toList();
                  if (visible.isEmpty) {
                    return const EmptyState(
                      icon: Icons.receipt_long_outlined,
                      title: 'Todavía no hay compras',
                      message: 'Cargá una compra a un proveedor con el botón '
                          '"Nueva compra".',
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                    itemCount: visible.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final p = visible[i];
                      return _PurchaseRow(
                        purchase: p,
                        supplier: suppliers[p.supplierId],
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => PurchaseEditScreen(purchase: p),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase, this.supplier, required this.onTap});

  final Purchase purchase;
  final Supplier? supplier;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    final draft = p.isDraft;
    final totalText =
        p.currency == 'USD' ? Fmt.usd(p.total) : Fmt.ars(p.total);
    return SurfaceCard(
      onTap: onTap,
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
                Text(supplier?.name ?? 'Sin proveedor',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
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
