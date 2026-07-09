import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';
import '../../ui/errors.dart';

/// RF-47 · Al reponer stock (cierre de compra, ajuste positivo, atribución):
/// si alguno de los productos tiene su publicación PAUSADA POR EL VENDEDOR,
/// ofrece reactivarla ahí mismo (push explícito de status=active). Las
/// pausadas por falta de stock no se listan: el push de stock que dispara la
/// misma reposición las reactiva solo (documentado por ML).
Future<void> maybeOfferReactivation(
  BuildContext context,
  WidgetRef ref,
  Iterable<String> productIds,
) async {
  // Economics puede estar desactualizado tras el import inicial: refrescar
  // antes de decidir sería costoso; usamos el snapshot y fallamos en silencio.
  final economics = ref.read(economicsByProductProvider);
  final paused = <ProductEconomics>[
    for (final id in productIds.toSet())
      if (economics[id] case final e?)
        if (e.mlItemId != null &&
            e.listingStatus == ListingStatus.paused &&
            e.isPausedBySeller)
          e,
  ];
  if (paused.isEmpty || !context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('¿Reactivar publicaciones?',
          style: TextStyle(color: AppColors.textPrimary, fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Volvió a haber stock de productos cuyas publicaciones pausaste '
            'en MercadoLibre:',
            style: TextStyle(color: AppColors.textMuted, height: 1.4),
          ),
          const SizedBox(height: 10),
          for (final e in paused.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('· ${e.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13.5)),
            ),
          if (paused.length > 6)
            Text('…y ${paused.length - 6} más',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Ahora no',
              style: TextStyle(color: AppColors.textMuted)),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
              'Reactivar ${paused.length == 1 ? 'la publicación' : '${paused.length} publicaciones'}'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;

  try {
    await ref
        .read(connectionRepositoryProvider)
        .reactivateListings([for (final e in paused) e.mlItemId!]);
    ref.invalidate(economicsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Publicaciones reactivadas en MercadoLibre')));
    }
  } catch (e) {
    if (context.mounted) {
      showAppError(context, e, title: 'No se pudo reactivar');
    }
  }
}
