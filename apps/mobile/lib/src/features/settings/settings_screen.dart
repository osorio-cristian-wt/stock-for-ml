import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env.dart';
import '../../data/economics_repository.dart';
import '../../data/pending_ops_service.dart';
import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../auth/app_lock.dart';
import '../auth/auth_controller.dart';
import '../categories/categories_screen.dart';
import '../connect_ml/connect_ml_screen.dart';
import '../connect_ml/import_prompt.dart';
import '../warehouses/warehouses_screen.dart';
import 'ml_activity_screen.dart';

/// 4th tab · Ajustes. Account, MercadoLibre connection, FX and sign out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(mlAccountProvider).valueOrNull;
    final fx = ref.watch(fxProvider).valueOrNull;
    final email = ref.watch(supabaseClientProvider).auth.currentUser?.email ?? '—';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          children: [
            const Text('Ajustes',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 18),
            const SectionHeader('Cuenta', uppercase: true),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.surfaceDeep,
                    child: Icon(Icons.person_outline, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const Text('Cuenta de Stock for ML',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('MercadoLibre', uppercase: true),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppColors.mlYellow,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.storefront, color: AppColors.onMlYellow, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account != null ? 'Cuenta conectada' : 'Sin conectar',
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary),
                            ),
                            Text(
                              account != null
                                  ? '${account.nickname ?? account.mlUserId} · ${account.siteId}'
                                  : 'Conectá para sincronizar publicaciones y ventas',
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      if (account != null)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ConnectMlScreen(standalone: true),
                          ),
                        );
                        ref.invalidate(mlAccountProvider);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: Text(account != null
                          ? 'Reconectar cuenta'
                          : 'Conectar con Mercado Libre'),
                    ),
                  ),
                  if (account != null) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        // RF-36: corre en segundo plano por lotes; el progreso
                        // se sigue desde el banner del Inicio.
                        onPressed: () => startImportInBackground(context, ref),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.surfaceDeep,
                          foregroundColor: AppColors.textPrimary,
                          minimumSize: const Size.fromHeight(46),
                        ),
                        label: const Text('Importar publicaciones'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MlActivityScreen()),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sync_alt_rounded, color: AppColors.primary),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Actividad ML',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text('Subidas de stock, imports y lo recibido desde ML',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppColors.textFaint),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Inventario', uppercase: true),
            const SizedBox(height: 10),
            SurfaceCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WarehousesScreen()),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warehouse_outlined, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Depósitos',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text('Principal de despacho, depósitos vendibles y transferencias',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textFaint),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SurfaceCard(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CategoriesScreen()),
              ),
              child: Row(
                children: [
                  const Icon(Icons.category_outlined, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Categorías',
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        Text('Crear, renombrar o eliminar tus categorías de productos',
                            style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textFaint),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Costeo', uppercase: true),
            const SizedBox(height: 10),
            const _CostPolicyCard(),
            const SizedBox(height: 18),
            const SectionHeader('Cotización', uppercase: true),
            const SizedBox(height: 10),
            SurfaceCard(
              child: Row(
                children: [
                  const Icon(Icons.attach_money_rounded, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      fx != null ? 'Dólar ${fx.kind}' : 'Dólar (sin datos)',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(fx != null ? Fmt.ars(fx.rate) : '—',
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if (fx?.fetchedAt != null)
                        Text('actualizado ${Fmt.ago(fx!.fetchedAt)}',
                            style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Actualizar cotización',
                    icon: const Icon(Icons.refresh_rounded,
                        size: 20, color: AppColors.textMuted),
                    onPressed: () async {
                      try {
                        await ref.read(economicsRepositoryProvider).refreshFx();
                      } catch (_) {
                        // Keep the last known value; the refresh just failed.
                      }
                      ref.invalidate(fxProvider);
                      ref.invalidate(dashboardProvider);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionHeader('Seguridad', uppercase: true),
            const SizedBox(height: 10),
            const _BiometricLockCard(),
            const SizedBox(height: 18),
            const SectionHeader('Zona peligrosa', uppercase: true),
            const SizedBox(height: 10),
            const _DangerZoneCard(),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => ref.read(authControllerProvider).signOut(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(50),
              ),
              label: const Text('Cerrar sesión'),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'Stock for ML · ${Env.isLocal ? "local" : "cloud"}',
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// RF-45 · Zona peligrosa: desconectar la cuenta de ML (conserva histórico) y
/// borrar TODOS los datos (nube + cache local) con confirmación fuerte.
class _DangerZoneCard extends ConsumerStatefulWidget {
  const _DangerZoneCard();

  @override
  ConsumerState<_DangerZoneCard> createState() => _DangerZoneCardState();
}

class _DangerZoneCardState extends ConsumerState<_DangerZoneCard> {
  bool _busy = false;

  Future<void> _disconnect() async {
    final account = ref.read(mlAccountProvider).valueOrNull;
    if (account == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Desconectar MercadoLibre?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: const Text(
          'Se revocan las credenciales y deja de sincronizar (stock, ventas, '
          'precios). Tus productos, ventas y publicaciones importadas se '
          'CONSERVAN. Podés reconectar cuando quieras.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child:
                const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(connectionRepositoryProvider).disconnectMl();
      ref.invalidate(mlAccountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Cuenta de ML desconectada · el histórico se conservó')));
      }
    } catch (e) {
      if (mounted) showAppError(context, e, title: 'No se pudo desconectar');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// RF-49: publicados → stock = available de su publicación ML; internos →
  /// 0. Repara drift acumulado (p. ej. negativos por doble descuento).
  Future<void> _recalibrate() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('¿Recalibrar stock?',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: const Text(
          'El stock vendible de cada producto se reescribe: los publicados '
          'quedan con las unidades que muestra su publicación en ML y los '
          'internos quedan en 0 (para recontar). No modifica nada en ML, no '
          'toca depósitos no vendibles ni el espejo Full, y las ventas y el '
          'historial se conservan.',
          style: TextStyle(color: AppColors.textMuted, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.warning),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Recalibrar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final adjusted =
          await ref.read(connectionRepositoryProvider).recalibrateStock();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(adjusted == 0
                ? 'Stock ya calibrado · nada que ajustar'
                : 'Stock recalibrado · $adjusted producto${adjusted == 1 ? '' : 's'} ajustado${adjusted == 1 ? '' : 's'}')));
      }
    } catch (e) {
      if (mounted) showAppError(context, e, title: 'No se pudo recalibrar');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _wipe() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _WipeConfirmDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(connectionRepositoryProvider).wipeAllData();
      // Cache local: la cola offline no debe subir ops de datos borrados.
      await ref.read(pendingOpsRepositoryProvider).clearAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Datos borrados · cerrando sesión')));
      }
      await ref.read(authControllerProvider).signOut();
    } catch (e) {
      if (mounted) showAppError(context, e, title: 'No se pudo borrar');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(mlAccountProvider).valueOrNull;
    return SurfaceCard(
      borderColor: AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (account != null) ...[
            OutlinedButton.icon(
              onPressed: _busy ? null : _disconnect,
              icon: const Icon(Icons.link_off_rounded, size: 18),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.danger,
                side: const BorderSide(color: AppColors.border),
                minimumSize: const Size.fromHeight(44),
              ),
              label: const Text('Desconectar MercadoLibre'),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: _busy ? null : _recalibrate,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.warning,
              side: const BorderSide(color: AppColors.border),
              minimumSize: const Size.fromHeight(44),
            ),
            label: const Text('Recalibrar stock'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _wipe,
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.danger,
              side: const BorderSide(color: AppColors.danger),
              minimumSize: const Size.fromHeight(44),
            ),
            label: const Text('Borrar todos los datos'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Borrar elimina productos, ventas, compras, depósitos y la conexión '
            'con ML — local y en la nube. No se puede deshacer.',
            style: TextStyle(fontSize: 11.5, color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Confirmación fuerte: hay que escribir BORRAR para habilitar el botón.
class _WipeConfirmDialog extends StatefulWidget {
  const _WipeConfirmDialog();

  @override
  State<_WipeConfirmDialog> createState() => _WipeConfirmDialogState();
}

class _WipeConfirmDialogState extends State<_WipeConfirmDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  bool get _armed => _text.text.trim().toUpperCase() == 'BORRAR';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('¿Borrar TODO?',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Se eliminan de forma permanente productos, stock, ventas, compras, '
            'clientes, proveedores, depósitos y la conexión con MercadoLibre. '
            'Escribí BORRAR para confirmar.',
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
            decoration: const InputDecoration(hintText: 'BORRAR'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child:
              const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          onPressed: _armed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Borrar todo'),
        ),
      ],
    );
  }
}

/// Bloqueo con Face ID / huella al volver a la app tras inactividad.
class _BiometricLockCard extends ConsumerWidget {
  const _BiometricLockCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final available = ref.watch(biometricsAvailableProvider).valueOrNull ?? false;
    final enabled = ref.watch(appLockEnabledProvider).valueOrNull ?? false;
    return SurfaceCard(
      child: Row(
        children: [
          const Icon(Icons.fingerprint_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bloqueo biométrico',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text(
                  available
                      ? 'Pide Face ID o huella al volver tras '
                          '${AppLock.timeout.inMinutes} min fuera de la app'
                      : 'Este dispositivo no tiene biometría configurada',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Switch(
            value: enabled && available,
            activeColor: AppColors.primary,
            onChanged: !available
                ? null
                : (v) async {
                    final ok = await setAppLockEnabled(ref, v);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text(
                              'No se pudo verificar la biometría; el bloqueo sigue apagado.')));
                    }
                  },
          ),
        ],
      ),
    );
  }
}

/// Política de valuación del costo de lo vendido (FIFO / promedio / última /
/// manual). Cambia cómo se calcula la ganancia neta en toda la app.
class _CostPolicyCard extends ConsumerWidget {
  const _CostPolicyCard();

  Future<void> _set(BuildContext context, WidgetRef ref, CostPolicy p) async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id ?? '';
    try {
      await ref.read(economicsRepositoryProvider).setCostPolicy(p, userId);
      ref.invalidate(costPolicyProvider);
      ref.invalidate(economicsProvider);
      ref.invalidate(saleProfitsProvider);
      ref.invalidate(dashboardProvider);
    } catch (e) {
      if (context.mounted) {
        showAppError(context, e, title: 'No se pudo cambiar la política');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current =
        ref.watch(costPolicyProvider).valueOrNull ?? CostPolicy.fifo;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Política de costo de lo vendido',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          const Text(
            'Define qué costo de compra se usa para calcular la ganancia '
            'de cada venta y la rentabilidad por producto.',
            style: TextStyle(
                fontSize: 12, color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),
          for (final p in CostPolicy.values) ...[
            InkWell(
              onTap: () => _set(context, ref, p),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    Icon(
                      p == current
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 19,
                      color:
                          p == current ? AppColors.primary : AppColors.textFaint,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: p == current
                                      ? AppColors.textPrimary
                                      : AppColors.textBody)),
                          Text(p.description,
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
