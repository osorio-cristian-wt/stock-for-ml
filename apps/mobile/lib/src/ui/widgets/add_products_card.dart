import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'app_widgets.dart';

/// Tarjeta explícita "Agregar productos" que encabeza la carga de una compra
/// o una venta (pedido del dueño: agregar → lista → guardar, siempre a la
/// vista, sin depender del FAB).
class AddProductsCard extends StatelessWidget {
  const AddProductsCard({
    super.key,
    required this.onScan,
    required this.onSearch,
    this.onInvoice,
  });

  final VoidCallback onScan;
  final VoidCallback onSearch;

  /// Solo compras: escanear la factura con la cámara (OCR).
  final VoidCallback? onInvoice;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.add_box_outlined, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text('Agregar productos',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onScan,
                  icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  label: const Text('Escanear'),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search, size: 18),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.borderStrong),
                    minimumSize: const Size(0, 46),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  label: const Text('Buscar'),
                ),
              ),
              if (onInvoice != null) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onInvoice,
                    icon: const Icon(Icons.document_scanner_outlined, size: 18),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.borderStrong),
                      minimumSize: const Size(0, 46),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    label: const Text('Factura'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
