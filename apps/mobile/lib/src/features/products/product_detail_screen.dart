import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';
import '../price_comparison/price_comparison_screen.dart';
import '../stock_adjustment/stock_adjustment_sheet.dart';
import '../stock_adjustment/transfer_sheet.dart';
import 'product_form_screen.dart';
import 'product_tile.dart' show ListingStatusChip;

/// Screen 05 · Detalle con rentabilidad por unidad. Reactive to the live
/// product stream, so a stock movement updates the numbers immediately.
class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);
    final economics = ref.watch(economicsByProductProvider)[productId];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle'),
        actions: [
          productsAsync.maybeWhen(
            data: (products) {
              final p = _find(products);
              if (p == null) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProductFormScreen(product: p),
                  ),
                ),
                child: const Text('Editar',
                    style: TextStyle(color: AppColors.textSecondary)),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: productsAsync.when(
        loading: () => const Loading(),
        error: (e, _) => InlineError(
          message: '$e',
          onRetry: () => ref.invalidate(productsStreamProvider),
        ),
        data: (products) {
          final p = _find(products);
          if (p == null) {
            return const EmptyState(
              icon: Icons.search_off,
              title: 'Producto no encontrado',
            );
          }
          return _Body(product: p, economics: economics);
        },
      ),
    );
  }

  Product? _find(List<Product> products) {
    for (final p in products) {
      if (p.id == productId) return p;
    }
    return null;
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.product, this.economics});

  final Product product;
  final ProductEconomics? economics;

  @override
  Widget build(BuildContext context) {
    final published = economics != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
      children: [
        _Header(product: product, economics: economics),
        const SizedBox(height: 16),
        if (published) ...[
          _ProfitCard(economics: economics!),
          _ChannelMarginsCard(product: product, economics: economics!),
        ] else
          _InternalCostCard(product: product),
        const SizedBox(height: 12),
        _StockCard(product: product),
        _WarehouseStockCard(product: product),
        if (published) _VariationsCard(listingId: economics!.listingId),
        _ListingsCard(productId: product.id),
        _HistoryCard(productId: product.id),
        if (published) ...[
          const SizedBox(height: 12),
          SurfaceCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PriceComparisonScreen(
                  listingId: economics!.listingId,
                  mlItemId: economics!.mlItemId,
                  title: product.title,
                ),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.insights_rounded, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Comparar precios en ML',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
                const Icon(Icons.chevron_right, color: AppColors.textFaint),
              ],
            ),
          ),
        ],
        if (!published) _LinkMlCard(product: product),
      ],
    );
  }
}

/// Lets the user pair an existing ML publication with this internal product.
/// Hidden when ML isn't connected. The publication title stays independent.
class _LinkMlCard extends ConsumerWidget {
  const _LinkMlCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = ref.watch(mlAccountProvider).valueOrNull != null;
    if (!connected) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SurfaceCard(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _LinkMlSheet(product: product),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.mlYellow,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.link_rounded, color: AppColors.onMlYellow, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vincular publicación de ML',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  Text('Buscá entre tus publicaciones importadas',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }
}

class _LinkMlSheet extends ConsumerStatefulWidget {
  const _LinkMlSheet({required this.product});

  final Product product;

  @override
  ConsumerState<_LinkMlSheet> createState() => _LinkMlSheetState();
}

/// RF-41: buscador sobre las publicaciones YA espejadas por sync-items —
/// nada de pegar el código a mano (queda como fallback para publicaciones
/// muy nuevas que todavía no se importaron).
class _LinkMlSheetState extends ConsumerState<_LinkMlSheet> {
  final _query = TextEditingController();
  List<MlListing> _results = const [];
  bool _searching = false;
  bool _busy = false;
  bool _manualMode = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Arranca sugiriendo por el título del producto (matcheo probable).
    _query.text = widget.product.title;
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    try {
      final rows = await ref
          .read(connectionRepositoryProvider)
          .searchListings(_query.text);
      if (mounted) setState(() => _results = rows);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo buscar. ${_firstLine(e)}');
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  static String _firstLine(Object e) => e.toString().split('\n').first;

  Future<void> _link(String mlItemId) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(connectionRepositoryProvider).linkListing(
            productId: widget.product.id,
            mlItemId: mlItemId.trim().toUpperCase(),
          );
      ref.invalidate(economicsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Publicación vinculada')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'No se pudo vincular. ${_firstLine(e)}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Vincular publicación de ML',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(widget.product.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 16),
              if (!_manualMode) ...[
                TextField(
                  controller: _query,
                  onSubmitted: (_) => _search(),
                  style:
                      const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Buscar por título o código…',
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.textFaint, size: 20),
                    suffixIcon: IconButton(
                      onPressed: _search,
                      icon: const Icon(Icons.arrow_forward_rounded,
                          color: AppColors.primary, size: 20),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: AppColors.primary),
                      ),
                    ),
                  )
                else if (_results.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Sin resultados entre tus publicaciones importadas. '
                      'Probá otro término o reimportá desde Ajustes.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final l = _results[i];
                        final linkedElsewhere = l.productId != null &&
                            l.productId != widget.product.id;
                        return SurfaceCard(
                          padding: const EdgeInsets.all(10),
                          onTap: _busy ? null : () => _link(l.mlItemId),
                          child: Row(
                            children: [
                              ProductThumb(
                                  imageUrl: l.thumbnail, size: 42, radius: 10),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(l.title ?? l.mlItemId,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary)),
                                    Text(
                                      '${l.mlItemId}${l.price != null ? ' · ${Fmt.ars(l.price!)}' : ''}'
                                      '${linkedElsewhere ? ' · ya vinculada (se re-vincula acá)' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11.5,
                                          color: AppColors.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.link_rounded,
                                  color: AppColors.primary, size: 18),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(() => _manualMode = true),
                  child: const Text('Ingresar el código (MLA…) a mano',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
              ] else ...[
                TextField(
                  controller: _query..clear(),
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  style:
                      const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(hintText: 'MLA1234567890'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : () => _link(_query.text),
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.4, color: AppColors.onPrimary),
                        )
                      : const Text('Vincular'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    _manualMode = false;
                    _query.text = widget.product.title;
                    _search();
                  }),
                  child: const Text('Volver al buscador',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(color: AppColors.danger, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.product, this.economics});

  final Product product;
  final ProductEconomics? economics;

  @override
  Widget build(BuildContext context) {
    final mlItemId = economics?.mlItemId;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProductThumb(imageUrl: product.imageUrl, size: 74, radius: 16),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.2)),
              const SizedBox(height: 3),
              Text(
                [
                  if (product.sku != null) product.sku,
                  if (mlItemId != null) mlItemId,
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  economics != null
                      ? TagChip('Activa',
                          color: AppColors.primary,
                          background: AppColors.primarySoft,
                          bold: true)
                      : const TagChip('Interno'),
                  if (product.gtin != null) ...[
                    const SizedBox(width: 6),
                    TagChip('GTIN ${product.gtin}'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfitCard extends StatelessWidget {
  const _ProfitCard({required this.economics});

  final ProductEconomics economics;

  @override
  Widget build(BuildContext context) {
    final e = economics;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Rentabilidad por unidad',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const SizedBox(height: 12),
          // RF-42: el precio de la publicación es de ML — read-only acá.
          InkWell(
            onTap: () => _showMlPriceInfo(context, e),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 9),
                  child: Row(
                    children: [
                      Text('Precio en ML',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textMuted)),
                      SizedBox(width: 5),
                      Icon(Icons.lock_outline_rounded,
                          size: 13, color: AppColors.textFaint),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Text(Fmt.ars(e.salePrice),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
          _Line(
            label: 'Comisión ML',
            value: '− ${Fmt.ars(e.estSaleFee)}',
            valueColor: AppColors.danger,
          ),
          if (e.hasCost)
            _Line(
              label: e.fxRate > 0
                  ? 'Costo (${Fmt.usd(e.costInSaleCurrency / e.fxRate)} × ${Fmt.ars(e.fxRate)})'
                  : 'Costo',
              value: '− ${Fmt.ars(e.costInSaleCurrency)}',
              valueColor: AppColors.danger,
            )
          else
            const _Line(
              label: 'Costo',
              value: 'sin cargar',
              valueColor: AppColors.warning,
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 11),
            child: Divider(height: 1, color: AppColors.border),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Ganancia neta',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text(
                e.netProfit == null ? '—' : Fmt.ars(e.netProfit!),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: e.netProfit == null
                      ? AppColors.textMuted
                      : e.netProfit! >= 0
                          ? AppColors.primary
                          : AppColors.danger,
                ),
              ),
            ],
          ),
          if (!e.hasCost)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Cargá el costo de compra para calcular ganancia, markup y margen.',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
              ),
            ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: _MiniStat(label: 'Markup', value: Fmt.pct(e.markupPct)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniStat(
                  label: 'Margen',
                  value: Fmt.pct(e.marginPct),
                  valueColor: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// RF-42: el precio de la publicación se administra en MercadoLibre; acá se
/// mira y, si hace falta cambiarlo, se abre la publicación.
void _showMlPriceInfo(BuildContext context, ProductEconomics e) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Precio administrado en ML',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
      content: const Text(
        'El precio de la publicación se modifica desde MercadoLibre. '
        'La app lo espeja automáticamente en cada sincronización.',
        style: TextStyle(color: AppColors.textMuted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Entendido',
              style: TextStyle(color: AppColors.textMuted)),
        ),
        if (e.permalink != null)
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              launchUrl(Uri.parse(e.permalink!),
                  mode: LaunchMode.externalApplication);
            },
            child: const Text('Abrir en ML'),
          ),
      ],
    ),
  );
}

/// RF-42 · Márgenes por canal: ML (precio publicación − comisión − costo) vs
/// venta local (precio local − costo). Ambos con el costo por política (ARS).
class _ChannelMarginsCard extends StatelessWidget {
  const _ChannelMarginsCard({required this.product, required this.economics});

  final Product product;
  final ProductEconomics economics;

  @override
  Widget build(BuildContext context) {
    final e = economics;
    final cost = e.hasCost ? e.costInSaleCurrency : null;

    final localPrice = product.salePrice;
    final localProfit = (cost != null && localPrice != null && localPrice > 0)
        ? localPrice - cost
        : null;
    final localMargin = (localProfit != null && localPrice! > 0)
        ? localProfit / localPrice * 100
        : null;
    final mlMargin = e.marginPct;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Márgenes por canal',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted)),
            const SizedBox(height: 12),
            _ChannelRow(
              label: 'MercadoLibre',
              detail: 'con comisión ML descontada',
              profit: e.netProfit,
              marginPct: mlMargin,
            ),
            const SizedBox(height: 10),
            _ChannelRow(
              label: 'Venta local',
              detail: localPrice == null || localPrice <= 0
                  ? 'sin precio local cargado'
                  : 'precio local ${Fmt.ars(localPrice)}',
              profit: localProfit,
              marginPct: localMargin,
            ),
            if (cost == null)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Cargá el costo de compra para ver los márgenes.',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.label,
    required this.detail,
    required this.profit,
    required this.marginPct,
  });

  final String label;
  final String detail;
  final double? profit;
  final double? marginPct;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              Text(detail,
                  style:
                      const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              profit == null ? '—' : Fmt.arsSigned(profit!),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: profit == null
                    ? AppColors.textMuted
                    : profit! >= 0
                        ? AppColors.primary
                        : AppColors.danger,
              ),
            ),
            Text(
              marginPct == null ? 'margen —' : 'margen ${Fmt.pct(marginPct)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}

class _InternalCostCard extends StatelessWidget {
  const _InternalCostCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Costo de compra',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textMuted)),
          const SizedBox(height: 10),
          Text(
            product.purchaseCurrency == 'USD'
                ? Fmt.usd(product.purchaseCost)
                : Fmt.ars(product.purchaseCost),
            style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Producto interno (sin publicación en ML). Vinculá una publicación '
            'para ver comisión, markup y margen reales.',
            style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _StockCard extends ConsumerWidget {
  const _StockCard({required this.product});

  final Product product;

  /// Edición rápida del umbral de stock bajo, sin pasar por el form completo.
  Future<void> _editThreshold(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: product.lowStockThreshold?.toString() ?? '',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Umbral de stock bajo',
            style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: 'Ej. 5 — vacío lo desactiva',
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child:
                const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (value == null || !context.mounted) return;
    try {
      // Update directo: copyWith no puede volver el umbral a null.
      await ref
          .read(supabaseClientProvider)
          .from('products')
          .update({'low_stock_threshold': value.isEmpty ? null : int.parse(value)})
          .eq('id', product.id);
    } catch (e) {
      if (context.mounted) {
        showAppError(context, e, title: 'No se pudo cambiar el umbral');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SurfaceCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Stock actual',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMuted)),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: '${product.currentStock} ',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    const TextSpan(
                      text: 'u.',
                      style: TextStyle(fontSize: 13, color: AppColors.textMuted),
                    ),
                  ]),
                ),
                InkWell(
                  onTap: () => _editThreshold(context, ref),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.lowStockThreshold != null
                            ? 'umbral: ${product.lowStockThreshold} u.'
                            : 'sin umbral de stock bajo',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.textMuted),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_outlined,
                          size: 13, color: AppColors.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // "Vender" vive en la pestaña Ventas (flujo carrito, como la compra).
          FilledButton(
            onPressed: () =>
                StockAdjustmentSheet.show(context, product: product),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Ajustar stock'),
          ),
        ],
      ),
    );
  }
}

/// Per-warehouse stock breakdown + transfer action. Always lists EVERY
/// warehouse (with 0 when the product has no stock there) so the detail says
/// exactly how the stock is distributed. Reactive to the live product_stock
/// stream; hidden only while the user has no warehouses at all.
class _WarehouseStockCard extends ConsumerWidget {
  const _WarehouseStockCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows =
        ref.watch(stockByWarehouseProvider(product.id)).valueOrNull ??
            const <ProductStock>[];
    final warehouses =
        ref.watch(warehousesStreamProvider).valueOrNull ?? const <Warehouse>[];
    if (warehouses.isEmpty) return const SizedBox.shrink();

    final byWarehouse = {for (final s in rows) s.warehouseId: s};
    final canTransfer = warehouses.length > 1;
    // One row per warehouse (default/principal first — the stream already
    // sorts that way), falling back to zeroed buckets.
    final shown = [
      for (final w in warehouses)
        (
          w,
          byWarehouse[w.id] ??
              ProductStock(productId: product.id, warehouseId: w.id),
        ),
    ];

    return Column(
      children: [
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Stock por depósito',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted)),
                  ),
                  if (canTransfer)
                    TextButton.icon(
                      onPressed: () =>
                          TransferSheet.show(context, product: product),
                      icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      label: const Text('Transferir'),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (final (w, s) in shown) ...[
                _WarehouseStockRow(stock: s, warehouse: w),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _WarehouseStockRow extends StatelessWidget {
  const _WarehouseStockRow({required this.stock, required this.warehouse});

  final ProductStock stock;
  final Warehouse warehouse;

  @override
  Widget build(BuildContext context) {
    final name =
        warehouse.name + (warehouse.isDefault ? ' · principal' : '');
    return Row(
      children: [
        const Icon(Icons.warehouse_outlined, size: 16, color: AppColors.textFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textBody,
                      fontWeight: FontWeight.w500)),
              if (stock.reserved != 0 || stock.incoming != 0) ...[
                const SizedBox(height: 3),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    if (stock.reserved != 0)
                      TagChip('Reservado ${stock.reserved}',
                          color: AppColors.warning,
                          background: AppColors.warningSoft),
                    if (stock.incoming != 0)
                      TagChip('En camino ${stock.incoming}'),
                  ],
                ),
              ],
            ],
          ),
        ),
        Text('${stock.available} disp.',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: stock.available > 0
                    ? AppColors.textPrimary
                    : AppColors.textMuted)),
      ],
    );
  }
}

/// ML-side stock per variation (talle/color/…) of the linked publication
/// (RF-07). Mirrored from ML by the sync; the app does not push item-level
/// stock to variation listings, so this breakdown is informative. Hidden for
/// simple listings.
class _VariationsCard extends ConsumerWidget {
  const _VariationsCard({required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variations =
        ref.watch(listingVariationsProvider(listingId)).valueOrNull ??
            const <ListingVariation>[];
    if (variations.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Variaciones (ML)',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted)),
              const SizedBox(height: 10),
              for (final v in variations) ...[
                Row(
                  children: [
                    const Icon(Icons.style_outlined,
                        size: 16, color: AppColors.textFaint),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.label,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textBody,
                                  fontWeight: FontWeight.w500)),
                          if (v.price != null)
                            Text(Fmt.ars(v.price!),
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    Text('${v.availableQuantity} u.',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const Text(
                'El stock por variación se administra en MercadoLibre; la app '
                'no lo empuja automáticamente.',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textMuted, height: 1.4),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// TODAS las publicaciones ML vinculadas al producto (RF-48). Un producto
/// puede tener varias (relistings, tipos de publicación) y la dedup del
/// import las colapsa acá — esta tarjeta las hace visibles y permite
/// pausar/activar cada una desde la app. Oculta si no hay ninguna.
class _ListingsCard extends ConsumerStatefulWidget {
  const _ListingsCard({required this.productId});

  final String productId;

  @override
  ConsumerState<_ListingsCard> createState() => _ListingsCardState();
}

class _ListingsCardState extends ConsumerState<_ListingsCard> {
  final Set<String> _busy = {};

  Future<void> _setStatus(MlListing l, String status) async {
    if (status == 'paused') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.surface,
          title: const Text('Pausar publicación',
              style: TextStyle(color: AppColors.textPrimary)),
          content: Text(
            '${l.title ?? l.mlItemId} deja de estar visible en MercadoLibre '
            'hasta que la actives de nuevo.',
            style: const TextStyle(color: AppColors.textMuted),
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
              child: const Text('Pausar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    setState(() => _busy.add(l.mlItemId));
    try {
      await ref
          .read(connectionRepositoryProvider)
          .setListingStatus([l.mlItemId], status);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'active'
              ? 'Publicación activada.'
              : 'Publicación pausada.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        showAppError(context, e,
            title: 'No se pudo cambiar el estado en ML');
      }
    } finally {
      if (mounted) setState(() => _busy.remove(l.mlItemId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final listings =
        ref.watch(productListingsProvider(widget.productId)).valueOrNull ??
            const <MlListing>[];
    if (listings.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Publicaciones (${listings.length})',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textMuted)),
              const SizedBox(height: 10),
              for (final l in listings) ...[
                _ListingRow(
                  listing: l,
                  busy: _busy.contains(l.mlItemId),
                  onActivate: () => _setStatus(l, 'active'),
                  onPause: () => _setStatus(l, 'paused'),
                ),
                if (l != listings.last)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Divider(height: 1, color: AppColors.border),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({
    required this.listing,
    required this.busy,
    required this.onActivate,
    required this.onPause,
  });

  final MlListing listing;
  final bool busy;
  final VoidCallback onActivate;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    // Pausada por el vendedor → se puede activar. Pausada por falta de stock
    // NO: ML la reactiva solo cuando sube stock (el botón mentiría).
    final canActivate = l.status == ListingStatus.paused && !l.isOutOfStock;
    final canPause = l.status == ListingStatus.active;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.title ?? l.mlItemId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 3),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ListingStatusChip.fromListing(l),
                  if (l.isFulfillment)
                    const TagChip('Full',
                        color: AppColors.onMlYellow,
                        background: AppColors.mlYellow,
                        bold: true),
                  Text(
                    [
                      l.mlItemId,
                      if (l.price != null) Fmt.ars(l.price!),
                      '${l.availableQuantity} u. en ML',
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        if (busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2.2, color: AppColors.primary),
          )
        else ...[
          if (canPause)
            IconButton(
              onPressed: onPause,
              tooltip: 'Pausar en ML',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.pause_circle_outline,
                  size: 20, color: AppColors.warning),
            ),
          if (canActivate)
            IconButton(
              onPressed: onActivate,
              tooltip: 'Activar en ML',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.play_circle_outline,
                  size: 20, color: AppColors.primary),
            ),
          if (l.permalink != null)
            IconButton(
              onPressed: () => launchUrl(Uri.parse(l.permalink!),
                  mode: LaunchMode.externalApplication),
              tooltip: 'Ver en ML',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.open_in_new_rounded,
                  size: 18, color: AppColors.textFaint),
            ),
        ],
      ],
    );
  }
}

/// Per-product timeline: purchases, adjustments, transfers and ML sales.
/// COLAPSABLE: arranca cerrado mostrando solo el resumen; el chevron del
/// header lo expande (pedido del dueño: el detalle no debe ser una sábana).
class _HistoryCard extends ConsumerStatefulWidget {
  const _HistoryCard({required this.productId});

  final String productId;

  @override
  ConsumerState<_HistoryCard> createState() => _HistoryCardState();
}

class _HistoryCardState extends ConsumerState<_HistoryCard> {
  bool _expanded = false;

  IconData _icon(HistoryKind k) => switch (k) {
        HistoryKind.sale => Icons.shopping_bag_outlined,
        HistoryKind.purchase => Icons.local_shipping_outlined,
        HistoryKind.adjustment => Icons.tune_rounded,
        HistoryKind.transfer => Icons.swap_horiz_rounded,
        HistoryKind.returned => Icons.undo_rounded,
        HistoryKind.initial => Icons.flag_outlined,
        HistoryKind.other => Icons.circle_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final entries =
        ref.watch(productHistoryProvider(widget.productId)).valueOrNull ??
            const <ProductHistoryEntry>[];
    if (entries.isEmpty) return const SizedBox.shrink();
    final shown = entries.take(30).toList();

    return Column(
      children: [
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Historial · ${entries.length} movimiento${entries.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textMuted),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(Icons.expand_more,
                          size: 20, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 12),
                for (var i = 0; i < shown.length; i++) ...[
                  _HistoryRow(
                    entry: shown[i],
                    icon: _icon(shown[i].kind),
                    productId: widget.productId,
                  ),
                  if (i != shown.length - 1)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 9),
                      child: Divider(height: 1, color: AppColors.border),
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.icon,
    required this.productId,
  });

  final ProductHistoryEntry entry;
  final IconData icon;
  final String productId;

  /// Subtítulo inmediato: la transferencia dice de qué depósito a cuál.
  String? get _subtitle {
    if (entry.kind == HistoryKind.transfer) {
      return '${entry.fromWarehouse ?? '¿?'} → ${entry.toWarehouse ?? '¿?'}';
    }
    if (entry.reference != null) {
      final r = entry.reference!;
      return '#${r.length > 12 ? r.substring(0, 12) : r}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final positive = entry.signedQty >= 0;
    final qtyText = '${positive ? '+' : '−'}${entry.signedQty.abs()} u';
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        builder: (_) =>
            _HistoryDetailSheet(entry: entry, icon: icon, productId: productId),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.label,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                if (_subtitle != null)
                  Text(_subtitle!,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(qtyText,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: positive ? AppColors.primary : AppColors.danger)),
              Text(Fmt.shortDate(entry.date),
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ],
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 16, color: AppColors.textFaint),
        ],
      ),
    );
  }
}

/// Detalle de una entrada del historial: precio de venta, depósitos de la
/// transferencia, depósito del movimiento, nota; el costo de una compra se
/// busca a demanda en purchase_items (no carga la consulta principal).
class _HistoryDetailSheet extends ConsumerWidget {
  const _HistoryDetailSheet({
    required this.entry,
    required this.icon,
    required this.productId,
  });

  final ProductHistoryEntry entry;
  final IconData icon;
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = entry;
    final positive = e.signedQty >= 0;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e.label,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
                Text(Fmt.shortDate(e.date),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textMuted)),
              ],
            ),
            const SizedBox(height: 14),
            _DetailRow(
              label: 'Cantidad',
              value: '${positive ? '+' : '−'}${e.signedQty.abs()} u.',
            ),
            if (e.unitPrice != null && e.unitPrice! > 0)
              _DetailRow(
                  label: 'Precio unitario', value: Fmt.ars(e.unitPrice!)),
            if (e.total != null && e.total! > 0)
              _DetailRow(label: 'Total', value: Fmt.ars(e.total!)),
            if (e.kind == HistoryKind.transfer)
              _DetailRow(
                label: 'Depósitos',
                value: '${e.fromWarehouse ?? '¿?'} → ${e.toWarehouse ?? '¿?'}',
              )
            else if (e.warehouseName != null)
              _DetailRow(label: 'Depósito', value: e.warehouseName!),
            if (e.kind == HistoryKind.purchase && e.reference != null)
              // Costo de la línea de compra, buscado recién al abrir el detalle.
              FutureBuilder<List<PurchaseItem>>(
                future: ref
                    .read(purchasesRepositoryProvider)
                    .itemsFor(e.reference!),
                builder: (context, snap) {
                  final items = snap.data;
                  if (items == null) return const SizedBox.shrink();
                  final line = [
                    for (final it in items)
                      if (it.productId == productId && it.unitCost > 0) it,
                  ];
                  if (line.isEmpty) return const SizedBox.shrink();
                  return _DetailRow(
                    label: 'Costo de compra',
                    value: '${Fmt.usd(line.first.unitCost)} c/u',
                  );
                },
              ),
            if (e.note != null && e.note!.isNotEmpty)
              _DetailRow(label: 'Nota', value: e.note!),
            if (e.reference != null)
              _DetailRow(label: 'Referencia', value: '#${e.reference}'),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: AppColors.textBody)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceDeep,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          const SizedBox(height: 1),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
