import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/env.dart';
import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../auth/auth_controller.dart';
import '../connect_ml/connect_ml_screen.dart';

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
                ],
              ),
            ),
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
                ],
              ),
            ),
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
