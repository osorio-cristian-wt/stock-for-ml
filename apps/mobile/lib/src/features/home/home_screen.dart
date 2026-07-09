import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../../ui/widgets/brand_logo.dart';
import '../connect_ml/connect_ml_screen.dart';
import '../products/product_detail_screen.dart';
import 'sync_banners.dart';

/// Screen 03 · Inicio. Dashboard with today's sales, profit, FX, counters and
/// the products that need restocking.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.onSeeAllLowStock,
    required this.onOpenAlerts,
  });

  final VoidCallback onSeeAllLowStock;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashAsync = ref.watch(dashboardProvider);
    final account = ref.watch(mlAccountProvider).valueOrNull;
    final unread = ref.watch(unreadAlertsCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            ref.invalidate(dashboardProvider);
            ref.invalidate(alertsProvider);
            ref.invalidate(pushIssuesProvider);
            ref.invalidate(fullInboundsProvider);
            await ref.read(dashboardProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _TopBar(
                connected: account != null,
                unread: unread,
                onBell: onOpenAlerts,
              ),
              const SizedBox(height: 20),
              if (account == null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ConnectBanner(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ConnectMlScreen(standalone: true),
                      ),
                    ),
                  ),
                ),
              const ImportProgressBanner(),
              const _PushIssuesBanner(),
              const FullInboundsBanner(),
              dashAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Loading(),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: InlineError(
                    message: '$e',
                    onRetry: () => ref.invalidate(dashboardProvider),
                  ),
                ),
                data: (d) => _Dashboard(
                  data: d,
                  onSeeAll: onSeeAllLowStock,
                  onOpenProduct: (p) => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(productId: p.id),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

/// Logo grande de la marca (Manual de Marca §01) + estado ML + campana.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.connected,
    required this.unread,
    required this.onBell,
  });

  final bool connected;
  final int unread;
  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: BrandLogo(markSize: 42, wordmarkSize: 23),
        ),
        StatusPill(
          label: connected ? 'ML conectado' : 'ML sin conectar',
          dotColor: connected ? AppColors.primary : AppColors.textFaint,
          glow: connected,
        ),
        const SizedBox(width: 10),
        _BellButton(unread: unread, onTap: onBell),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: AppColors.border),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.notifications_none_rounded,
                size: 20, color: AppColors.textSecondary),
            if (unread > 0)
              Positioned(
                top: 8,
                right: 9,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.surface, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({
    required this.data,
    required this.onSeeAll,
    required this.onOpenProduct,
  });

  final DashboardData data;
  final VoidCallback onSeeAll;
  final ValueChanged<Product> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SalesCard(data: data),
        const SizedBox(height: 12),
        if (data.fx != null) _FxRow(fx: data.fx!),
        if (data.fx != null) const SizedBox(height: 14),
        _Counters(data: data),
        const SizedBox(height: 18),
        SectionHeader(
          'Necesitan reposición',
          actionLabel: data.lowStock.isEmpty ? null : 'Ver todo',
          onAction: onSeeAll,
        ),
        const SizedBox(height: 11),
        if (data.lowStock.isEmpty)
          SurfaceCard(
            child: Row(
              children: const [
                Icon(Icons.check_circle_outline, color: AppColors.primary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Todo tu stock está por encima del umbral. 👌',
                      style: TextStyle(fontSize: 13, color: AppColors.textBody)),
                ),
              ],
            ),
          )
        else
          ...data.lowStock.take(4).map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: _LowStockRow(product: p, onTap: () => onOpenProduct(p)),
                ),
              ),
      ],
    );
  }
}

class _SalesCard extends StatelessWidget {
  const _SalesCard({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Ventas de hoy',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 3),
                    Text(
                      Fmt.ars(data.todaySalesGross),
                      style: const TextStyle(
                          fontSize: 29,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.5),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${data.todaySalesCount} ${data.todaySalesCount == 1 ? "venta" : "ventas"}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 13),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            children: [
              Expanded(
                child: _Metric(
                  label: 'Ganancia neta',
                  value: Fmt.ars(data.todayNetProfit),
                  valueColor: AppColors.primary,
                ),
              ),
              Expanded(
                child: _Metric(
                  label: 'Margen prom.',
                  value: Fmt.pct(data.avgMarginPct),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 1),
        Text(value,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: valueColor ?? AppColors.textPrimary)),
      ],
    );
  }
}

class _FxRow extends StatelessWidget {
  const _FxRow({required this.fx});

  final FxRate fx;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Text('\$',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('Dólar ${fx.kind} (hoy)',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.ars(fx.rate),
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Text('costo USD→ARS',
                  style: TextStyle(fontSize: 10, color: AppColors.primary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Counters extends StatelessWidget {
  const _Counters({required this.data});

  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _CounterCard(
            value: '${data.lowStockCount}',
            label: 'Stock bajo',
            color: data.lowStockCount > 0 ? AppColors.warning : AppColors.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CounterCard(value: '${data.listingsCount}', label: 'Publicaciones'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _CounterCard(value: '${data.todaySalesCount}', label: 'Ventas hoy'),
        ),
      ],
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      radius: 16,
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: color ?? AppColors.textPrimary,
                  letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.product, required this.onTap});

  final Product product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final out = product.currentStock <= 0;
    return SurfaceCard(
      onTap: onTap,
      radius: 16,
      padding: const EdgeInsets.all(11),
      child: Row(
        children: [
          ProductThumb(imageUrl: product.imageUrl, size: 42, radius: 11),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary)),
                Text(
                  product.sku ?? 'sin SKU',
                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: out ? AppColors.dangerSoft : AppColors.warningSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              Fmt.units(product.currentStock),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: out ? AppColors.danger : AppColors.warning,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Quedaron N productos sin subir a ML": pushes en error (o demorados) que
/// antes fallaban en silencio. Tap → detalle por producto + reintento.
class _PushIssuesBanner extends ConsumerWidget {
  const _PushIssuesBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = ref.watch(pushIssuesProvider).valueOrNull ?? const [];
    if (issues.isEmpty) return const SizedBox.shrink();
    final failed = issues.where((i) => i.status == 'error').length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SurfaceCard(
        color: AppColors.warningSoft,
        borderColor: AppColors.warning,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const _PushIssuesSheet(),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failed > 0
                        ? 'Stock sin subir a ML: ${issues.length} producto${issues.length == 1 ? '' : 's'}'
                        : 'Subida de stock a ML demorada (${issues.length})',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                  const Text('Tocá para ver el detalle y reintentar',
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

class _PushIssuesSheet extends ConsumerStatefulWidget {
  const _PushIssuesSheet();

  @override
  ConsumerState<_PushIssuesSheet> createState() => _PushIssuesSheetState();
}

class _PushIssuesSheetState extends ConsumerState<_PushIssuesSheet> {
  bool _busy = false;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      await ref.read(connectionRepositoryProvider).retryPush();
      ref.invalidate(pushIssuesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Reintento disparado — revisá en unos segundos.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) showAppError(context, e, title: 'No se pudo reintentar');
    }
  }

  @override
  Widget build(BuildContext context) {
    final issues = ref.watch(pushIssuesProvider).valueOrNull ?? const [];
    final products = {
      for (final p in ref.watch(productsStreamProvider).valueOrNull ??
          const <Product>[])
        p.id: p,
    };
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Stock sin subir a MercadoLibre',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            const Text(
              'Estos cambios de stock todavía no llegaron a ML (por conexión '
              'u otro error). El stock local está bien; falta el push.',
              style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: issues.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final issue = issues[i];
                  final p = products[issue.productId];
                  return SurfaceCard(
                    radius: 13,
                    padding: const EdgeInsets.all(11),
                    child: Row(
                      children: [
                        Icon(
                          issue.status == 'error'
                              ? Icons.error_outline
                              : Icons.schedule,
                          size: 18,
                          color: issue.status == 'error'
                              ? AppColors.danger
                              : AppColors.warning,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p?.title ?? 'Producto',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              Text(
                                issue.status == 'error'
                                    ? (issue.error ??
                                        'Error tras ${issue.attempts} intento(s)')
                                    : 'Pendiente de subir',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _retry,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.2, color: AppColors.onPrimary),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar ahora'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectBanner extends StatelessWidget {
  const _ConnectBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      onTap: onTap,
      color: AppColors.primarySoft,
      borderColor: AppColors.primary,
      child: Row(
        children: [
          const Icon(Icons.link_rounded, color: AppColors.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Conectá tu cuenta de ML',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                Text('Para importar publicaciones, ventas y comisiones',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.primary),
        ],
      ),
    );
  }
}
