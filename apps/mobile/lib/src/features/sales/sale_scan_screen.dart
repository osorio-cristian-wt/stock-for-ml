import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../data/queries.dart';
import '../products/product_form_screen.dart';
import '../purchases/qty_cost_sheet.dart';
import '../scan/scanner_chrome.dart';

/// Carga continua de una VENTA (mismo flujo que la compra): la cámara queda
/// abierta; cada código conocido abre cantidad/precio y vuelve a la cámara;
/// un código nuevo pasa por el alta de producto. "Finalizar" regresa al
/// carrito de la venta. Las líneas viven en el carrito del caller (la venta
/// se escribe en una sola transacción al confirmarla).
class SaleScanScreen extends ConsumerStatefulWidget {
  const SaleScanScreen({
    super.key,
    required this.onAddLine,
    required this.suggestedPrice,
  });

  /// Suma la línea confirmada al carrito del caller.
  final void Function(Product product, int qty, double unitPrice) onAddLine;

  /// Precio sugerido para prellenar (ej. el precio de la publicación ML).
  final double Function(Product product) suggestedPrice;

  static Future<void> open(
    BuildContext context, {
    required void Function(Product, int, double) onAddLine,
    required double Function(Product) suggestedPrice,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SaleScanScreen(
          onAddLine: onAddLine,
          suggestedPrice: suggestedPrice,
        ),
      ),
    );
  }

  @override
  ConsumerState<SaleScanScreen> createState() => _SaleScanScreenState();
}

class _SaleScanScreenState extends ConsumerState<SaleScanScreen> {
  final _controller = buildScannerController();
  bool _paused = false;
  bool _torch = false;
  int _added = 0;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Product? _findByCode(String code) {
    final all = ref.read(productsStreamProvider).valueOrNull ?? const <Product>[];
    final scanned = ScannedCode.classify(code);
    final keys = {
      code.toLowerCase(),
      if (scanned.gtin != null) scanned.gtin!.toLowerCase(),
    };
    for (final p in all) {
      if (keys.contains(p.sku?.toLowerCase()) ||
          keys.contains(p.gtin?.toLowerCase())) {
        return p;
      }
    }
    return null;
  }

  Future<Product?> _waitForProduct(String code) async {
    for (var i = 0; i < 10; i++) {
      final p = _findByCode(code);
      if (p != null) return p;
      await Future.delayed(const Duration(milliseconds: 300));
    }
    return null;
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_paused) return;
    String? raw;
    for (final b in capture.barcodes) {
      if (b.rawValue != null && b.rawValue!.trim().isNotEmpty) {
        raw = b.rawValue!.trim();
        break;
      }
    }
    if (raw == null) return;
    final now = DateTime.now();
    if (raw == _lastCode &&
        now.difference(_lastAt) < const Duration(seconds: 3)) {
      return;
    }
    _lastCode = raw;
    _lastAt = now;
    await HapticFeedback.mediumImpact();
    await _handleCode(raw);
  }

  Future<void> _handleCode(String code) async {
    setState(() => _paused = true);
    try {
      var product = _findByCode(code);
      if (product == null) {
        final scanned = ScannedCode.classify(code);
        final created = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => ProductFormScreen(
              initialGtin: scanned.isGtin ? scanned.gtin : null,
              initialSku: scanned.isGtin ? null : code,
            ),
          ),
        );
        if (created != true || !mounted) return;
        product = await _waitForProduct(code);
        if (product == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Producto creado; escanealo de nuevo para sumarlo.')));
          }
          return;
        }
      }
      if (!mounted) return;
      final p = product;
      if (p.currentStock <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('“${p.title}” no tiene stock disponible.')));
        return;
      }
      var confirmed = false;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => QtyCostSheet(
          title: p.title,
          initialQty: 1,
          initialCost: widget.suggestedPrice(p),
          priceLabel: 'Precio unitario (ARS)',
          confirmLabel: 'Agregar a la venta',
          onConfirm: (qty, price) async {
            widget.onAddLine(p, qty, price);
            confirmed = true;
          },
        ),
      );
      if (confirmed && mounted) setState(() => _added++);
    } finally {
      if (mounted) setState(() => _paused = false);
    }
  }

  Future<void> _manualEntry() async {
    final code = await promptManualCode(context);
    if (code == null || code.isEmpty || !mounted) return;
    await _handleCode(code.trim());
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
          const ScannerScrim(),
          SafeArea(
            child: Column(
              children: [
                ScannerTopBar(
                  title: 'Venta · carga continua',
                  torch: _torch,
                  onClose: () => Navigator.of(context).pop(),
                  onTorch: () async {
                    await _controller.toggleTorch();
                    setState(() => _torch = !_torch);
                  },
                ),
                const Spacer(),
                ScannerHint(
                  title: 'Escaneá lo que estás vendiendo',
                  subtitle: 'Existe → cantidad y precio. Nuevo → alta y luego '
                      'cantidad. Después de cada uno volvés a la cámara.',
                ),
                const SizedBox(height: 12),
                ScannerManualButton(onPressed: _manualEntry),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(_added == 0
                          ? 'Volver a la venta'
                          : 'Volver a la venta · $_added línea${_added == 1 ? '' : 's'}'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
