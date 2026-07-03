import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// Isotipo de la marca (caja isométrica en trazo) del Manual de Marca §01.
/// Dibujado como vector propio para que quede nítido a cualquier tamaño sin
/// sumar dependencias de SVG. La fuente canónica vive en docs/brand/.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40, this.color = AppColors.primary});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BrandMarkPainter(color),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Coordenadas del viewBox 0..64 del manual, escaladas al tamaño pedido.
    final s = size.width / 64;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * s
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final hex = Path()
      ..moveTo(p(32, 6).dx, p(32, 6).dy)
      ..lineTo(p(56, 18).dx, p(56, 18).dy)
      ..lineTo(p(56, 46).dx, p(56, 46).dy)
      ..lineTo(p(32, 58).dx, p(32, 58).dy)
      ..lineTo(p(8, 46).dx, p(8, 46).dy)
      ..lineTo(p(8, 18).dx, p(8, 18).dy)
      ..close();
    canvas.drawPath(hex, stroke);

    final topV = Path()
      ..moveTo(p(8, 18).dx, p(8, 18).dy)
      ..lineTo(p(32, 30).dx, p(32, 30).dy)
      ..lineTo(p(56, 18).dx, p(56, 18).dy);
    canvas.drawPath(topV, stroke);

    canvas.drawLine(p(32, 30), p(32, 58), stroke);

    final diagonal = Paint()
      ..color = color.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * s
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(p(20, 12), p(44, 24), diagonal);
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Lockup completo: isotipo + wordmark Stock·for·ML (+ tagline opcional).
/// Es la "versión principal" del manual, pensada para fondos Carbón.
class BrandLogo extends StatelessWidget {
  const BrandLogo({
    super.key,
    this.markSize = 40,
    this.wordmarkSize = 22,
    this.showTagline = true,
  });

  final double markSize;
  final double wordmarkSize;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(size: markSize),
        SizedBox(width: markSize * 0.28),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: wordmarkSize,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  letterSpacing: wordmarkSize * -0.02,
                  height: 1,
                ),
                children: const [
                  TextSpan(text: 'Stock'),
                  TextSpan(
                    text: 'for',
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: AppColors.textMuted,
                    ),
                  ),
                  TextSpan(
                    text: 'ML',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ],
              ),
            ),
            if (showTagline) ...[
              SizedBox(height: wordmarkSize * 0.22),
              Text(
                'STOCK · RENTABILIDAD',
                style: AppTheme.mono(
                  fontSize: wordmarkSize * 0.34,
                  fontWeight: FontWeight.w400,
                  color: AppColors.textFaint,
                  letterSpacing: wordmarkSize * 0.1,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
