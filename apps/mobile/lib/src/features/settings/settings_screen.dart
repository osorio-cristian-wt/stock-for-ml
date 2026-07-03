import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env.dart';
import '../../data/economics_repository.dart';
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
import '../warehouses/warehouses_screen.dart';

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
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          messenger.showSnackBar(const SnackBar(
                              content: Text('Importando publicaciones de ML…')));
                          try {
                            await ref
                                .read(connectionRepositoryProvider)
                                .triggerInitialSync();
                            ref.invalidate(productsStreamProvider);
                            ref.invalidate(economicsProvider);
                            messenger.showSnackBar(const SnackBar(
                                content: Text('Importación iniciada. Tus '
                                    'productos se irán actualizando.')));
                          } catch (e) {
                            messenger.showSnackBar(
                                SnackBar(content: Text('No se pudo importar. $e')));
                          }
                        },
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
