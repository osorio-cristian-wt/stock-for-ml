import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/import_service.dart';
import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/widgets/app_widgets.dart';

/// RF-36 · Progreso del import de publicaciones en el Inicio. Se alimenta por
/// Realtime de `import_jobs`, así avanza aunque los lotes los procese el cron
/// del backend y no esta instancia de la app.
class ImportProgressBanner extends ConsumerWidget {
  const ImportProgressBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(activeImportJobProvider);
    if (job == null) return const SizedBox.shrink();

    if (job.status == 'error') {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SurfaceCard(
          color: AppColors.warningSoft,
          borderColor: AppColors.warning,
          onTap: () => ref.read(importServiceProvider).start(),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.warning),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('El import de publicaciones falló',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text(
                      job.errors.isEmpty
                          ? 'Tocá para reintentar (retoma donde quedó)'
                          : job.errors.last,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textMuted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.refresh_rounded, color: AppColors.warning),
            ],
          ),
        ),
      );
    }

    final total = job.total;
    final done = job.processed + job.failed;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    total == null
                        ? 'Importando publicaciones…'
                        : 'Importando publicaciones · $done de $total',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
                if (job.failed > 0)
                  Text('${job.failed} con error',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.warning)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.progress,
                minHeight: 5,
                backgroundColor: AppColors.surfaceDeep,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 6),
            const Text('Sigue en segundo plano aunque cierres la app',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint)),
          ],
        ),
      ),
    );
  }
}

/// RF-38 · Mercadería nueva detectada en Full pendiente de atribuir: el
/// usuario dice de qué depósito local salió (descuento SOLO local, sin push a
/// ML) o la descarta (p. ej. compra que entró directa a Full).
class FullInboundsBanner extends ConsumerWidget {
  const FullInboundsBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbounds = ref.watch(fullInboundsProvider).valueOrNull ?? const [];
    if (inbounds.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        color: AppColors.warningSoft,
        borderColor: AppColors.warning,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _FullInboundsSheet(),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_shipping_outlined, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mercadería nueva en Full (${inbounds.length})',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  const Text('Indicá de qué depósito salió para descontarla',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.warning),
          ],
        ),
      ),
    );
  }
}

class _FullInboundsSheet extends ConsumerStatefulWidget {
  const _FullInboundsSheet();

  @override
  ConsumerState<_FullInboundsSheet> createState() => _FullInboundsSheetState();
}

class _FullInboundsSheetState extends ConsumerState<_FullInboundsSheet> {
  String? _busyId;

  Future<void> _attribute(FullInbound inbound, Warehouse warehouse) async {
    setState(() => _busyId = inbound.id);
    try {
      await ref.read(connectionRepositoryProvider).attributeFullInbound(
            inboundId: inbound.id,
            warehouseId: warehouse.id,
          );
      ref.invalidate(fullInboundsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Descontado de ${warehouse.name} (solo local, sin subir a ML)')));
      }
    } catch (e) {
      if (mounted) showAppError(context, e, title: 'No se pudo atribuir');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _dismiss(FullInbound inbound) async {
    setState(() => _busyId = inbound.id);
    try {
      await ref.read(connectionRepositoryProvider).dismissFullInbound(inbound.id);
      ref.invalidate(fullInboundsProvider);
    } catch (e) {
      if (mounted) showAppError(context, e, title: 'No se pudo descartar');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _pickWarehouse(FullInbound inbound) async {
    final warehouses =
        (ref.read(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[])
            .where((w) => !w.mlFulfillment)
            .toList();
    final chosen = await showModalBottomSheet<Warehouse>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 16, 22, 6),
              child: Text('¿De qué depósito salió?',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
            for (final w in warehouses)
              ListTile(
                leading: const Icon(Icons.warehouse_outlined,
                    color: AppColors.textSecondary),
                title: Text(w.name,
                    style: const TextStyle(color: AppColors.textPrimary)),
                subtitle: w.isDefault
                    ? const Text('Depósito de despacho',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textMuted))
                    : null,
                onTap: () => Navigator.of(ctx).pop(w),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) await _attribute(inbound, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final inbounds = ref.watch(fullInboundsProvider).valueOrNull ?? const [];
    final products = {
      for (final p
          in ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[])
        p.id: p,
    };

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Mercadería nueva en Full',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            const Text(
              'ML recibió stock en sus depósitos Full. Si salió de un depósito '
              'tuyo, elegilo para descontarlo localmente (no se sube a ML: '
              'ellos ya lo contaron). Si entró directo a Full, descartalo.',
              style:
                  TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: inbounds.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final inbound = inbounds[i];
                  final product = products[inbound.productId];
                  final busy = _busyId == inbound.id;
                  return SurfaceCard(
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
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              Text('+${inbound.qty} unidad${inbound.qty == 1 ? '' : 'es'} en Full',
                                  style: const TextStyle(
                                      fontSize: 12, color: AppColors.textMuted)),
                            ],
                          ),
                        ),
                        if (busy)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.2, color: AppColors.primary),
                          )
                        else ...[
                          TextButton(
                            onPressed: () => _dismiss(inbound),
                            child: const Text('Descartar',
                                style: TextStyle(color: AppColors.textMuted)),
                          ),
                          FilledButton(
                            onPressed: () => _pickWarehouse(inbound),
                            child: const Text('Atribuir'),
                          ),
                        ],
                      ],
                    ),
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
