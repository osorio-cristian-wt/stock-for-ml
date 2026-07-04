import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_db.dart';
import '../../data/pending_ops_repository.dart';
import '../../data/pending_ops_service.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';

/// Sección "Pendientes de subir" del feed de Movimientos (misma estética que
/// Borradores): operaciones confirmadas SIN red que esperan sincronizarse.
/// Una op rechazada por el server al sincronizar (ej. el stock ya no alcanza)
/// queda marcada en rojo con el detalle, para reintentar o descartar.
class PendingOpsSection extends ConsumerWidget {
  const PendingOpsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops =
        ref.watch(pendingOpsProvider).valueOrNull ?? const <PendingOp>[];
    if (ops.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Pendientes de subir', uppercase: true),
        const SizedBox(height: 10),
        for (final op in ops) ...[
          _PendingOpRow(op: op),
          const SizedBox(height: 9),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

String _kindLabel(String kind) => switch (kind) {
      PendingOpKind.sale => 'Venta',
      PendingOpKind.purchaseClose => 'Cierre de compra',
      PendingOpKind.transfer => 'Transferencia',
      PendingOpKind.adjust => 'Ajuste de stock',
      _ => 'Operación',
    };

class _PendingOpRow extends ConsumerWidget {
  const _PendingOpRow({required this.op});

  final PendingOp op;

  bool get _failed => op.status == PendingOpStatus.error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SurfaceCard(
      radius: 15,
      padding: const EdgeInsets.all(11),
      borderColor: _failed ? AppColors.danger : AppColors.border,
      onTap: () => _showDetail(context, ref),
      child: Row(
        children: [
          Icon(
            _failed ? Icons.error_outline_rounded : Icons.schedule_rounded,
            size: 20,
            color: _failed ? AppColors.danger : AppColors.warning,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(op.summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(width: 6),
                    _failed
                        ? TagChip('Rechazada',
                            color: AppColors.danger,
                            background: AppColors.dangerSoft,
                            bold: true)
                        : TagChip('Pendiente',
                            color: AppColors.warning,
                            background: AppColors.warningSoft,
                            bold: true),
                  ],
                ),
                Text(
                  '${_kindLabel(op.kind)} · ${Fmt.ago(op.createdAt)}',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
        ],
      ),
    );
  }

  Future<void> _showDetail(BuildContext context, WidgetRef ref) {
    // Se capturan antes de los await: la fila puede desmontarse al mutar la
    // cola (y un ref de widget descartado no se puede usar).
    final repo = ref.read(pendingOpsRepositoryProvider);
    final service = ref.read(pendingOpsServiceProvider);
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(_kindLabel(op.kind),
            style: const TextStyle(color: AppColors.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(op.summary,
                  style: const TextStyle(
                      color: AppColors.textBody, fontSize: 14, height: 1.4)),
              const SizedBox(height: 10),
              Text(
                _failed
                    ? 'El servidor la rechazó al sincronizar'
                        '${op.attempts > 1 ? ' (${op.attempts} intentos)' : ''}:'
                    : 'Se sube automáticamente cuando vuelve la conexión.',
                style: TextStyle(
                    color: _failed ? AppColors.danger : AppColors.textMuted,
                    fontSize: 12,
                    height: 1.4),
              ),
              if (_failed && op.lastError != null) ...[
                const SizedBox(height: 6),
                Text(AppErrors.friendly(op.lastError!),
                    style: const TextStyle(
                        color: AppColors.textBody, fontSize: 13, height: 1.4)),
                const SizedBox(height: 14),
                const Text('Detalle técnico',
                    style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(op.lastError!,
                    style: const TextStyle(
                        color: AppColors.textFaint, fontSize: 11, height: 1.4)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final ok = await _confirmDiscard(ctx);
              if (ok && ctx.mounted) {
                await repo.delete(op.id);
                if (ctx.mounted) Navigator.of(ctx).pop();
              }
            },
            child:
                const Text('Descartar', style: TextStyle(color: AppColors.danger)),
          ),
          TextButton(
            onPressed: () async {
              // Pendiente: fuerza un drenado ya. Rechazada: vuelve a pending
              // y el worker la retoma.
              if (_failed) {
                await repo.resetToPending(op.id);
              }
              if (ctx.mounted) Navigator.of(ctx).pop();
              await service.drain();
            },
            child: Text(_failed ? 'Reintentar' : 'Subir ahora',
                style: const TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cerrar', style: TextStyle(color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDiscard(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Descartar operación',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Esta ${_kindLabel(op.kind).toLowerCase()} nunca se subió al '
          'servidor: si la descartás, no queda registrada.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
