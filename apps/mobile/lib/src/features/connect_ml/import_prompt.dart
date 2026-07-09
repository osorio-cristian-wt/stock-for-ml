import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/import_service.dart';
import '../../theme/app_colors.dart';

bool _offeredThisSession = false;

/// Tras el primer login exitoso con ML, ofrece importar las publicaciones del
/// vendedor ahí mismo (RF-05). Se muestra una sola vez por sesión y es seguro
/// repetirlo: el import es idempotente (dedup por GTIN/SKU, no pisa stock).
///
/// RF-36: ya no bloquea con un diálogo — el import corre en segundo plano por
/// lotes (server-side) y el progreso se ve en el banner del Inicio, con el
/// cron del backend como red de seguridad si se cierra la app.
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
        '¿Importamos tus publicaciones de MercadoLibre ahora? Corre en '
        'segundo plano y se crean como productos de stock (sin duplicar '
        'los que ya tengas).',
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

  startImportInBackground(context, ref);
}

/// Lanza el import sin bloquear y avisa dónde seguir el progreso.
void startImportInBackground(BuildContext context, WidgetRef ref) {
  unawaited(ref.read(importServiceProvider).start());
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text('Importando en segundo plano · seguí el avance en Inicio'),
  ));
}
