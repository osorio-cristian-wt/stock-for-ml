import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_colors.dart';
import '../products/product_detail_screen.dart';
import '../products/product_form_screen.dart';
import '../stock_adjustment/stock_adjustment_sheet.dart';
import 'catalog_result_sheet.dart';

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
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.qrCode,
    ],
  );
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
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Ingresar código', style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'EAN/UPC o SKU'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
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
                _CameraError(onManual: _manualEntry),
          ),
          // Dim + reticle overlay.
          const _ScrimWithHole(),
          SafeArea(
            child: Column(
              children: [
                _TopBar(
                  torch: _torch,
                  onClose: () => Navigator.of(context).pop(),
                  onTorch: () async {
                    await _controller.toggleTorch();
                    setState(() => _torch = !_torch);
                  },
                ),
                const Spacer(),
                const _Hint(),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  child: OutlinedButton.icon(
                    onPressed: _manualEntry,
                    icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: Colors.black.withValues(alpha: 0.35),
                    ),
                    label: const Text('Ingresar código manualmente'),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.torch, required this.onClose, required this.onTorch});

  final bool torch;
  final VoidCallback onClose;
  final VoidCallback onTorch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _RoundIcon(icon: Icons.close, onTap: onClose),
          const Text('Escanear producto',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          _RoundIcon(
            icon: torch ? Icons.flash_on : Icons.flash_off,
            active: torch,
            onTap: onTorch,
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap, this.active = false});

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: active ? AppColors.onPrimary : Colors.white, size: 22),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        children: [
          Text('Apuntá al código de barras',
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          SizedBox(height: 6),
          Text(
            'EAN/UPC busca la ficha en el catálogo de ML. '
            'Un código alfanumérico se toma como SKU interno.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Dark scrim with a transparent rounded window and emerald corner brackets.
class _ScrimWithHole extends StatelessWidget {
  const _ScrimWithHole();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final boxW = w * 0.74;
        final boxH = boxW * 0.62;
        return Stack(
          children: [
            // Scrim with a hole punched out via blend mode.
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.55),
                BlendMode.srcOut,
              ),
              child: Stack(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Center(
                    child: Container(
                      width: boxW,
                      height: boxH,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: SizedBox(
                width: boxW,
                height: boxH,
                child: CustomPaint(painter: _BracketPainter()),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const len = 26.0;
    const r = 22.0;
    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(0, r + len)
        ..lineTo(0, r)
        ..arcToPoint(const Offset(r, 0), radius: const Radius.circular(r))
        ..lineTo(r + len, 0),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width - r - len, 0)
        ..lineTo(size.width - r, 0)
        ..arcToPoint(Offset(size.width, r), radius: const Radius.circular(r))
        ..lineTo(size.width, r + len),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height - r - len)
        ..lineTo(size.width, size.height - r)
        ..arcToPoint(Offset(size.width - r, size.height), radius: const Radius.circular(r))
        ..lineTo(size.width - r - len, size.height),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(r + len, size.height)
        ..lineTo(r, size.height)
        ..arcToPoint(Offset(0, size.height - r), radius: const Radius.circular(r))
        ..lineTo(0, size.height - r - len),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.onManual});

  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography_outlined, size: 44, color: AppColors.textFaint),
          const SizedBox(height: 14),
          const Text('Cámara no disponible',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text(
            'Revisá los permisos de cámara o ingresá el código a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onManual,
            icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
            label: const Text('Ingresar código'),
          ),
        ],
      ),
    );
  }
}
