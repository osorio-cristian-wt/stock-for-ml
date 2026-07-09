import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';
import '../../ui/format.dart';
import '../../ui/widgets/app_widgets.dart';

/// RF-40.3 · "Completar costos": recorre uno por uno los productos sin costo
/// de compra para dejarlos costeados sin salir a buscar cada uno por la lista.
/// Sin costo no hay ganancia calculada (RF-40), así que esta vista es la vía
/// rápida para que las stats vuelvan a ser reales.
class CompleteCostsScreen extends ConsumerStatefulWidget {
  const CompleteCostsScreen({super.key});

  @override
  ConsumerState<CompleteCostsScreen> createState() =>
      _CompleteCostsScreenState();
}

class _CompleteCostsScreenState extends ConsumerState<CompleteCostsScreen> {
  /// Cola de ids pendientes, congelada al entrar (no "salta" si el stream
  /// refresca); los guardados/salteados salen de la cola.
  List<String>? _queue;
  final _cost = TextEditingController();
  String _currency = 'USD';
  bool _busy = false;

  @override
  void dispose() {
    _cost.dispose();
    super.dispose();
  }

  double get _costValue =>
      double.tryParse(_cost.text.trim().replaceAll(',', '.')) ?? 0;

  List<Product> _pending(List<Product> products) =>
      [for (final p in products) if (p.purchaseCost <= 0) p];

  void _next() {
    setState(() {
      _queue = [...?_queue]..removeAt(0);
      _cost.clear();
      _currency = 'USD';
    });
  }

  Future<void> _save(Product p) async {
    if (_costValue <= 0) return;
    setState(() => _busy = true);
    try {
      await ref.read(productsRepositoryProvider).update(
            p.copyWith(purchaseCost: _costValue, purchaseCurrency: _currency),
          );
      ref.invalidate(economicsProvider);
      _next();
    } catch (e) {
      if (mounted) showAppError(context, e, title: 'No se pudo guardar');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final products =
        ref.watch(productsStreamProvider).valueOrNull ?? const <Product>[];
    final byId = {for (final p in products) p.id: p};
    _queue ??= [for (final p in _pending(products)) p.id];

    // Productos borrados mientras la pantalla está abierta salen solos.
    final queue = [
      for (final id in _queue!)
        if (byId.containsKey(id)) byId[id]!,
    ];

    final economics = ref.watch(economicsByProductProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Completar costos')),
      body: queue.isEmpty
          ? const EmptyState(
              icon: Icons.task_alt_rounded,
              title: '¡Todo costeado!',
              message:
                  'Todos tus productos tienen costo de compra: la ganancia y '
                  'los márgenes ya se calculan completos.',
            )
          : _buildEditor(queue, economics),
    );
  }

  Widget _buildEditor(
    List<Product> queue,
    Map<String, ProductEconomics> economics,
  ) {
    final p = queue.first;
    final e = economics[p.id];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      children: [
        Text('${queue.length} pendiente${queue.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        const SizedBox(height: 12),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProductThumb(imageUrl: p.imageUrl, size: 64, radius: 14),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 3),
                        Text(
                          [
                            if (p.sku != null) p.sku!,
                            if (e != null) 'ML ${Fmt.ars(e.salePrice)}',
                            if (p.salePrice != null && p.salePrice! > 0)
                              'local ${Fmt.ars(p.salePrice!)}',
                          ].join(' · '),
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('Costo de compra (por unidad)',
                  style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _cost,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      style: const TextStyle(
                          color: AppColors.textPrimary, fontSize: 15),
                      decoration: const InputDecoration(hintText: '8,50'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CurrencyToggle(
                    currency: _currency,
                    onChanged: (c) => setState(() => _currency = c),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _next,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textMuted,
                        side: const BorderSide(color: AppColors.border),
                        minimumSize: const Size.fromHeight(46),
                      ),
                      child: const Text('Saltar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed:
                          _busy || _costValue <= 0 ? null : () => _save(p),
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.4, color: AppColors.onPrimary),
                            )
                          : const Text('Guardar y seguir'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CurrencyToggle extends StatelessWidget {
  const _CurrencyToggle({required this.currency, required this.onChanged});

  final String currency;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final c in const ['USD', 'ARS'])
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: GestureDetector(
              onTap: () => onChanged(c),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: currency == c ? AppColors.primarySoft : AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color:
                          currency == c ? AppColors.primary : AppColors.border),
                ),
                child: Text(c,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: currency == c
                            ? AppColors.primary
                            : AppColors.textSecondary)),
              ),
            ),
          ),
      ],
    );
  }
}
