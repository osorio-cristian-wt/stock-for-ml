import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../theme/app_colors.dart';

/// Shared visual chrome for the full-screen scanners ([ScanScreen] and
/// [CodeScannerScreen]): dark scrim with reticle, top bar with torch,
/// manual-entry affordances and the camera-error fallback.

/// Controller preset shared by every scanner (barcode formats we sell with).
MobileScannerController buildScannerController() {
  return MobileScannerController(
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
}

/// Dialog fallback when the camera can't read the code (or isn't available).
/// Resolves with the trimmed code, or null when cancelled.
Future<String?> promptManualCode(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Ingresar código',
          style: TextStyle(color: AppColors.textPrimary)),
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
}

class ScannerTopBar extends StatelessWidget {
  const ScannerTopBar({
    super.key,
    required this.title,
    required this.torch,
    required this.onClose,
    required this.onTorch,
  });

  final String title;
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
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
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

class ScannerHint extends StatelessWidget {
  const ScannerHint({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 36),
      child: Column(
        children: [
          Text(title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// "Ingresar código manualmente" pinned under the reticle.
class ScannerManualButton extends StatelessWidget {
  const ScannerManualButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24),
          minimumSize: const Size.fromHeight(50),
          backgroundColor: Colors.black.withValues(alpha: 0.35),
        ),
        label: const Text('Ingresar código manualmente'),
      ),
    );
  }
}

/// Dark scrim with a transparent rounded window and emerald corner brackets.
class ScannerScrim extends StatelessWidget {
  const ScannerScrim({super.key});

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

class ScannerCameraError extends StatelessWidget {
  const ScannerCameraError({super.key, required this.onManual});

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
