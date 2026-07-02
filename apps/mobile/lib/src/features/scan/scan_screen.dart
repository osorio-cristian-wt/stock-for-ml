import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../products/product_detail_screen.dart';
import '../products/product_form_screen.dart';
import '../stock_adjustment/stock_adjustment_sheet.dart';
import 'catalog_result_sheet.dart';
import 'scanner_chrome.dart';

/// Scan + catalog check (barcode-first product loading). Full-screen camera
/// with a focused reticle. A detected code runs the cascade in
/// [CatalogResultSheet]; GTINs go to the ML catalog, internal SKUs to manual
/// load. Creative latitude was taken here, per the brief.
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _controller = buildScannerController();
  bool _handled = false;
  bool _torch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _resume() async {
    if (!mounted) return;
    setState(() => _handled = false);
    try {
      await _controller.start();
    } catch (_) {/* already running */}
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    String? raw;
    for (final b in capture.barcodes) {
      if (b.rawValue != null && b.rawValue!.isNotEmpty) {
        raw = b.rawValue;
        break;
      }
    }
    if (raw == null) return;
    _handled = true;
    await HapticFeedback.mediumImpact();
    try {
      await _controller.stop();
    } catch (_) {}
    await _process(ScannedCode.classify(raw));
  }

  Future<void> _manualEntry() async {
    final code = await promptManualCode(context);
    if (code == null || code.isEmpty || !mounted) return;
    _handled = true;
    try {
      await _controller.stop();
    } catch (_) {}
    await _process(ScannedCode.classify(code));
  }

  Future<void> _process(ScannedCode code) async {
    final outcome = await CatalogResultSheet.show(context, code);
    if (!mounted) return;

    switch (outcome?.decision) {
      case null:
      case ScanDecision.rescan:
        await _resume();
      case ScanDecision.openExisting:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => ProductDetailScreen(productId: outcome!.existing!.id),
          ),
        );
      case ScanDecision.addStockExisting:
        await StockAdjustmentSheet.show(context, product: outcome!.existing!);
        if (mounted) Navigator.of(context).pop();
      case ScanDecision.create:
        final saved = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => ProductFormScreen(
              initialGtin: code.isGtin ? code.gtin : null,
              initialSku: code.isGtin ? null : code.raw,
              initialTitle: outcome?.enrichment?.name,
              initialBrand: outcome?.enrichment?.brand,
              initialCategoryId: outcome?.enrichment?.categoryId,
              initialImageUrl: outcome?.enrichment?.imageUrl,
            ),
          ),
        );
        if (!mounted) return;
        if (saved == true) {
          Navigator.of(context).pop();
        } else {
          await _resume();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) =>
                ScannerCameraError(onManual: _manualEntry),
          ),
          // Dim + reticle overlay.
          const ScannerScrim(),
          SafeArea(
            child: Column(
              children: [
                ScannerTopBar(
                  title: 'Escanear producto',
                  torch: _torch,
                  onClose: () => Navigator.of(context).pop(),
                  onTorch: () async {
                    await _controller.toggleTorch();
                    setState(() => _torch = !_torch);
                  },
                ),
                const Spacer(),
                const ScannerHint(
                  title: 'Apuntá al código de barras',
                  subtitle: 'EAN/UPC busca la ficha en el catálogo de ML. '
                      'Un código alfanumérico se toma como SKU interno.',
                ),
                const SizedBox(height: 18),
                ScannerManualButton(onPressed: _manualEntry),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
