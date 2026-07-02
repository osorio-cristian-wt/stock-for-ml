import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/catalog_repository.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';

/// What the user chose on the scan-result sheet.
enum ScanDecision { rescan, openExisting, addStockExisting, create }

class ScanOutcome {
  const ScanOutcome(this.decision, {this.existing, this.code, this.enrichment});

  final ScanDecision decision;
  final Product? existing;
  final ScannedCode? code;
  final ProductEnrichment? enrichment;
}

/// Bottom sheet shown after a successful scan. It runs the barcode-first
/// cascade: (1) "does this code already exist?", then for a GTIN the catalog
/// enrichment (ML catalog → ML category predictor → LLM fallback). Designed
/// freely — the goal is a confident, one-glance decision.
class CatalogResultSheet extends ConsumerStatefulWidget {
  const CatalogResultSheet({super.key, required this.code});

  final ScannedCode code;

  static Future<ScanOutcome?> show(BuildContext context, ScannedCode code) {
    return showModalBottomSheet<ScanOutcome>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => CatalogResultSheet(code: code),
    );
  }

  @override
  ConsumerState<CatalogResultSheet> createState() => _CatalogResultSheetState();
}

enum _Phase { checking, existing, enriching, matched, noMatch, error }

class _CatalogResultSheetState extends ConsumerState<CatalogResultSheet> {
  _Phase _phase = _Phase.checking;
  Product? _existing;
  ProductEnrichment? _enrichment;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      // 1) Already in the catalog?
      final existing =
          await ref.read(productsRepositoryProvider).findByCode(widget.code.raw);
      if (!mounted) return;
      if (existing != null) {
        setState(() {
          _existing = existing;
          _phase = _Phase.existing;
        });
        return;
      }

      // 2) Internal SKU → nothing to enrich, go straight to manual load.
      if (!widget.code.isGtin) {
        setState(() => _phase = _Phase.noMatch);
        return;
      }

      // 3) GTIN → enrich against ML catalog / category predictor.
      setState(() => _phase = _Phase.enriching);
      final enrichment =
          await ref.read(catalogRepositoryProvider).lookup(widget.code);
      if (!mounted) return;
      setState(() {
        _enrichment = enrichment;
        _phase = enrichment.hasMatch ? _Phase.matched : _Phase.noMatch;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().split('\n').first;
          _phase = _Phase.noMatch; // degrade gracefully to manual load
        });
      }
    }
  }

  void _close(ScanOutcome outcome) => Navigator.of(context).pop(outcome);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _CodeChip(code: widget.code),
            const SizedBox(height: 18),
            _content(),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    switch (_phase) {
      case _Phase.checking:
        return const _Status(text: 'Revisando tu catálogo…');
      case _Phase.enriching:
        return const _Status(text: 'Buscando la ficha en MercadoLibre…');
      case _Phase.existing:
        return _ExistingView(
          product: _existing!,
          onOpen: () => _close(ScanOutcome(ScanDecision.openExisting,
              existing: _existing, code: widget.code)),
          onAddStock: () => _close(ScanOutcome(ScanDecision.addStockExisting,
              existing: _existing, code: widget.code)),
        );
      case _Phase.matched:
        return _MatchView(
          enrichment: _enrichment!,
          onUse: () => _close(ScanOutcome(ScanDecision.create,
              code: widget.code, enrichment: _enrichment)),
          onManual: () => _close(ScanOutcome(ScanDecision.create, code: widget.code)),
        );
      case _Phase.noMatch:
      case _Phase.error:
        return _NoMatchView(
          isGtin: widget.code.isGtin,
          note: _error,
          onContinue: () =>
              _close(ScanOutcome(ScanDecision.create, code: widget.code)),
          onRescan: () => _close(const ScanOutcome(ScanDecision.rescan)),
        );
    }
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});

  final ScannedCode code;

  @override
  Widget build(BuildContext context) {
    final isGtin = code.isGtin;
    final color = isGtin ? AppColors.primary : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceDeep,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(isGtin ? Icons.qr_code_2_rounded : Icons.tag_rounded,
              color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(code.raw,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5)),
                Text(
                  isGtin ? 'Código de barras (EAN/UPC)' : 'Código interno (SKU)',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 26),
      child: Row(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
          ),
          const SizedBox(width: 14),
          Text(text,
              style: const TextStyle(fontSize: 14, color: AppColors.textBody)),
        ],
      ),
    );
  }
}

class _ExistingView extends StatelessWidget {
  const _ExistingView({
    required this.product,
    required this.onOpen,
    required this.onAddStock,
  });

  final Product product;
  final VoidCallback onOpen;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Ya está en tu catálogo',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    Text('${product.sku ?? "sin SKU"} · ${product.currentStock} u.',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onAddStock, child: const Text('Sumar stock')),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onOpen,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('Ver producto'),
        ),
      ],
    );
  }
}

class _MatchView extends StatelessWidget {
  const _MatchView({
    required this.enrichment,
    required this.onUse,
    required this.onManual,
  });

  final ProductEnrichment enrichment;
  final VoidCallback onUse;
  final VoidCallback onManual;

  String get _sourceLabel {
    switch (enrichment.source) {
      case 'ml_catalog':
        return 'Ficha de catálogo de ML';
      case 'ml_domain':
        return 'Categoría sugerida por ML';
      case 'llm':
        return 'Sugerido por IA';
      default:
        return 'Coincidencia';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.check, size: 16, color: AppColors.onPrimary),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Encontramos una coincidencia',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.primary),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(enrichment.name ?? 'Producto',
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  if (enrichment.brand != null) _Tag(enrichment.brand!),
                  if (enrichment.categoryName != null) _Tag(enrichment.categoryName!),
                  if (enrichment.categoryId != null && enrichment.categoryName == null)
                    _Tag(enrichment.categoryId!),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.verified_outlined, size: 14, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(_sourceLabel,
                      style: const TextStyle(fontSize: 11, color: AppColors.primary)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: onUse, child: const Text('Usar estos datos')),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onManual,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('Cargar a mano'),
        ),
      ],
    );
  }
}

class _NoMatchView extends StatelessWidget {
  const _NoMatchView({
    required this.isGtin,
    required this.onContinue,
    required this.onRescan,
    this.note,
  });

  final bool isGtin;
  final String? note;
  final VoidCallback onContinue;
  final VoidCallback onRescan;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(isGtin ? 'Sin ficha en el catálogo' : 'Código interno detectado',
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text(
          isGtin
              ? 'No encontramos este código en MercadoLibre. Es habitual con '
                  'importados. Cargá los datos a mano y se publica libre con su GTIN.'
              : 'Es un SKU tuyo, no un código de barras global. Completá los '
                  'datos del producto.',
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted, height: 1.4),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          Text('Nota: $note',
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
        ],
        const SizedBox(height: 18),
        FilledButton(onPressed: onContinue, child: const Text('Continuar carga manual')),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: onRescan,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size.fromHeight(50),
          ),
          child: const Text('Escanear otro'),
        ),
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 12, color: AppColors.textBody)),
    );
  }
}
