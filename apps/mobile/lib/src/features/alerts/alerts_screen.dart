import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';

/// Screen 09 · Alertas. Stock and sales notifications, split into "Nuevas"
/// (unread) and "Anteriores" (read), with a "Marcar leídas" action.
class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsProvider);

    Future<void> markAll() async {
      await ref.read(alertsRepositoryProvider).markAllRead();
      ref.invalidate(alertsProvider);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alertas'),
        actions: [
          alertsAsync.maybeWhen(
            data: (alerts) => alerts.any((a) => !a.isRead)
                ? TextButton(
                    onPressed: markAll,
                    child: const Text('Marcar leídas',
                        style: TextStyle(color: AppColors.primary, fontSize: 13)),
                  )
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: alertsAsync.when(
        loading: () => const Loading(),
        error: (e, _) => InlineError(
          message: '$e',
          onRetry: () => ref.invalidate(alertsProvider),
        ),
        data: (alerts) {
          if (alerts.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_off_outlined,
              title: 'Sin alertas',
              message: 'Te avisaremos cuando un producto quede bajo de stock o '
                  'entre una venta.',
            );
          }
          final unread = alerts.where((a) => !a.isRead).toList();
          final read = alerts.where((a) => a.isRead).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (unread.isNotEmpty) ...[
                const SectionHeader('Nuevas', uppercase: true),
                const SizedBox(height: 10),
                for (final a in unread) ...[
                  _AlertCard(alert: a, onTap: () => _markOne(ref, a)),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 10),
              ],
              if (read.isNotEmpty) ...[
                const SectionHeader('Anteriores', uppercase: true),
                const SizedBox(height: 10),
                for (final a in read) ...[
                  _AlertCard(alert: a, dim: true),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _markOne(WidgetRef ref, AppAlert alert) async {
    await ref.read(alertsRepositoryProvider).markRead(alert.id);
    ref.invalidate(alertsProvider);
  }
}

class _AlertVisual {
  const _AlertVisual(this.icon, this.color, this.title);
  final IconData icon;
  final Color color;
  final String title;
}

_AlertVisual _visualFor(AlertType type) {
  switch (type) {
    case AlertType.outOfStock:
      return const _AlertVisual(Icons.remove_shopping_cart_rounded,
          AppColors.danger, 'Sin stock');
    case AlertType.lowStock:
      return const _AlertVisual(
          Icons.warning_amber_rounded, AppColors.warning, 'Stock bajo');
    case AlertType.newOrder:
      return const _AlertVisual(
          Icons.bar_chart_rounded, AppColors.primary, 'Nueva venta');
    case AlertType.priceChange:
      return const _AlertVisual(
          Icons.price_change_rounded, AppColors.primary, 'Cambio de precio');
    case AlertType.unknown:
      return const _AlertVisual(
          Icons.notifications_rounded, AppColors.textSecondary, 'Aviso');
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, this.onTap, this.dim = false});

  final AppAlert alert;
  final VoidCallback? onTap;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final v = _visualFor(alert.type);
    return Opacity(
      opacity: dim ? 0.7 : 1,
      child: SurfaceCard(
        onTap: onTap,
        radius: 15,
        padding: const EdgeInsets.all(13),
        color: dim ? AppColors.surfaceDeep : AppColors.surface,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: v.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(v.icon, color: v.color, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  if (alert.message != null) ...[
                    const SizedBox(height: 2),
                    Text(alert.message!,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary, height: 1.4)),
                  ],
                  const SizedBox(height: 5),
                  Text(Fmt.ago(alert.createdAt),
                      style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
                ],
              ),
            ),
            if (!alert.isRead)
              Container(
                margin: const EdgeInsets.only(top: 2, left: 6),
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
