import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';

bool _offeredThisSession = false;

/// Tras el primer login exitoso con ML, ofrece importar las publicaciones del
/// vendedor ahí mismo (RF-05). Se muestra una sola vez por sesión y es seguro
/// repetirlo: el import es idempotente (dedup por GTIN/SKU, no pisa stock).
Future<void> offerInitialImport(BuildContext context, WidgetRef ref) async {
  if (_offeredThisSession) return;
  _offeredThisSession = true;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Cuenta conectada',
          style: TextStyle(color: AppColors.textPrimary)),
      content: const Text(
        '¿Importamos tus publicaciones de MercadoLibre ahora? Se crean como '
        'productos de stock (sin duplicar los que ya tengas).',
        style: TextStyle(color: AppColors.textMuted, height: 1.4),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child:
              const Text('Más tarde', style: TextStyle(color: AppColors.textMuted)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Importar'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  // Blocking progress while sync-items runs server-side.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      backgroundColor: AppColors.surface,
      content: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
                strokeWidth: 2.4, color: AppColors.primary),
          ),
          SizedBox(width: 16),
          Expanded(
            child: Text('Importando publicaciones…',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14)),
          ),
        ],
      ),
    ),
  );

  String? error;
  try {
    await ref.read(connectionRepositoryProvider).triggerInitialSync();
  } catch (e) {
    error = e.toString().split('\n').first;
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // cierra el progreso

  ref.invalidate(productsStreamProvider);
  ref.invalidate(economicsProvider);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(error == null
        ? 'Publicaciones importadas · revisá Productos'
        : 'No se pudo importar: $error'),
  ));
}
