import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/connection_repository.dart';
import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';

/// RF-46 · "Actividad ML": qué se subió a ML (pushes de stock), qué llegó
/// desde ML (ventas, espejo Full, imports) y en qué estado quedó cada cosa.
/// Cierra RNF-07: nada de esto era visible fuera de la base.
class MlActivityScreen extends ConsumerWidget {
  const MlActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(mlActivityProvider);
    final products = {
      for (final p
          in ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[])
        p.id: p,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Actividad ML')),
      body: activity.when(
        loading: () => const Loading(),
        error: (e, _) => InlineError(
          message: '$e',
          onRetry: () => ref.invalidate(mlActivityProvider),
        ),
        data: (a) => RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(mlActivityProvider);
            await ref.read(mlActivityProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            children: [
              const SectionHeader('Imports de publicaciones', uppercase: true),
              const SizedBox(height: 8),
              if (a.jobs.isEmpty)
                const _EmptyLine('Sin imports todavía.')
              else
                for (final j in a.jobs) _ImportRow(job: j),
              const SizedBox(height: 18),
              const SectionHeader('Subidas de stock a ML', uppercase: true),
              const SizedBox(height: 8),
              if (a.pushes.isEmpty)
                const _EmptyLine('Sin pushes registrados.')
              else
                for (final p in a.pushes)
                  _PushRow(entry: p, product: products[p.productId]),
              const SizedBox(height: 18),
              const SectionHeader('Recibido desde ML', uppercase: true),
              const SizedBox(height: 8),
              if (a.mlMovements.isEmpty)
                const _EmptyLine('Sin movimientos originados en ML.')
              else
                for (final m in a.mlMovements)
                  _MovementRow(movement: m, product: products[m.productId]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Snapshot de las tres fuentes de actividad.
class MlActivity {
  const MlActivity({
    required this.jobs,
    required this.pushes,
    required this.mlMovements,
  });

  final List<ImportJob> jobs;
  final List<StockPushEntry> pushes;
  final List<StockMovement> mlMovements;
}

final mlActivityProvider = FutureProvider<MlActivity>((ref) async {
  final repo = ref.watch(connectionRepositoryProvider);
  final results = await Future.wait([
    repo.recentImportJobs(),
    repo.recentPushes(),
    repo.recentMlMovements(),
  ]);
  return MlActivity(
    jobs: results[0] as List<ImportJob>,
    pushes: results[1] as List<StockPushEntry>,
    mlMovements: results[2] as List<StockMovement>,
  );
});

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Text(text,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
    );
  }
}

class _ImportRow extends StatelessWidget {
  const _ImportRow({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (job.status) {
      'done' => ('Completado', AppColors.primary),
      'error' => ('Error', AppColors.danger),
      _ => ('En curso', AppColors.warning),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.total == null
                        ? '${job.processed} publicaciones'
                        : '${job.processed} de ${job.total} publicaciones'
                          '${job.failed > 0 ? ' · ${job.failed} con error' : ''}',
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  if (job.startedAt != null)
                    Text(Fmt.ago(job.startedAt),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            TagChip(label, color: color, bold: true),
          ],
        ),
      ),
    );
  }
}

class _PushRow extends StatelessWidget {
  const _PushRow({required this.entry, this.product});

  final StockPushEntry entry;
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (entry.status) {
      'done' => ('Subido', AppColors.primary),
      'error' => ('Falló', AppColors.danger),
      'processing' => ('Subiendo', AppColors.warning),
      _ => ('Pendiente', AppColors.warning),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
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
                  Text(
                    [
                      if (entry.enqueuedAt != null) Fmt.ago(entry.enqueuedAt),
                      if (entry.attempts > 1) '${entry.attempts} intentos',
                      if (entry.error != null) entry.error!,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            TagChip(label, color: color, bold: true),
          ],
        ),
      ),
    );
  }
}

class _MovementRow extends StatelessWidget {
  const _MovementRow({required this.movement, this.product});

  final StockMovement movement;
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final label = switch (movement.reason) {
      StockReason.reserve => 'Venta ML · reserva',
      StockReason.dispatch => 'Venta ML · despacho',
      StockReason.cancellation => 'Cancelación ML',
      StockReason.returned => 'Devolución ML',
      StockReason.initialSync => 'Import inicial',
      StockReason.fullSync => 'Espejo Full',
      StockReason.fullInbound => 'Atribución Full',
      _ => 'Movimiento ML',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
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
                  Text(
                    '$label${movement.createdAt != null ? ' · ${Fmt.ago(movement.createdAt)}' : ''}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
            Text(
              '${movement.delta > 0 ? '+' : ''}${movement.delta}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: movement.delta >= 0 ? AppColors.primary : AppColors.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
