import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

/// Manejo de errores centralizado de la app: un solo lugar traduce las
/// excepciones (PostgREST/RPC, funciones Edge, auth, red) a un mensaje corto
/// en el tono de la marca, y [showAppError] las muestra siempre igual (snack
/// con detalle expandible), en vez de `e.toString()` crudo en cada pantalla.
abstract final class AppErrors {
  /// Mensaje corto apto para el usuario. Nunca incluye stack traces.
  static String friendly(Object error) {
    if (error is AppException) return error.message;

    // Sin conexión / DNS / timeout: el caso más común en la operatoria móvil.
    if (error is SocketException ||
        error is TimeoutException ||
        error is HttpException) {
      return 'Sin conexión. Revisá tu internet e intentá de nuevo.';
    }

    // Errores de la base / RPCs (create_local_sale, transfer_stock, etc.).
    // Los `raise exception` propios ya vienen en español → se muestran tal cual.
    if (error is PostgrestException) {
      final msg = error.message.trim();
      if (msg.contains('JWT') || error.code == 'PGRST301') {
        return 'La sesión venció. Volvé a iniciar sesión.';
      }
      if (error.code == '23505') {
        return 'Ya existe un registro con esos datos (¿SKU o código repetido?).';
      }
      if (error.code == '23514') {
        return 'Algún valor no pasa las validaciones (revisá cantidades y precios).';
      }
      return _sentence(msg.isEmpty ? 'Error de base de datos.' : msg);
    }

    // Funciones Edge (lookup-product, parse-invoice, push…).
    if (error is FunctionException) {
      final details = error.details;
      final detailMsg = details is Map ? details['error']?.toString() : null;
      if (error.status >= 500) {
        return 'El servidor tuvo un problema. Intentá de nuevo en un momento.';
      }
      return _sentence(detailMsg ?? 'No se pudo completar la operación (HTTP ${error.status}).');
    }

    if (error is AuthException) {
      return _sentence(error.message);
    }

    // ClientException de package:http (lo lanza supabase sin red) llega como
    // Exception genérica con "Connection" en el texto.
    final s = error.toString();
    if (s.contains('SocketException') ||
        s.contains('Connection') ||
        s.contains('Failed host lookup')) {
      return 'Sin conexión. Revisá tu internet e intentá de nuevo.';
    }

    final first = s.split('\n').first.replaceFirst(RegExp(r'^\w*Exception:?\s*'), '');
    return _sentence(first.length > 140 ? '${first.substring(0, 140)}…' : first);
  }

  /// ¿El error huele a falta de conectividad? (para decidir reintentos)
  static bool isOffline(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    final s = error.toString();
    return s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection refused') ||
        s.contains('Connection reset');
  }

  static String _sentence(String s) {
    final t = s.trim();
    if (t.isEmpty) return 'Algo salió mal.';
    final capped = t[0].toUpperCase() + t.substring(1);
    return capped.endsWith('.') ? capped : '$capped.';
  }
}

/// Error de dominio con mensaje ya pensado para mostrar.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Muestra un error de operación de forma consistente: snack en rojo con el
/// contexto de QUÉ falló ("No se registró la venta"), el motivo traducido y
/// "Detalles" para ver el error técnico completo.
void showAppError(
  BuildContext context,
  Object error, {
  required String title,
}) {
  final friendly = AppErrors.friendly(error);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 6),
      content: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$title\n',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.danger),
          ),
          TextSpan(
            text: friendly,
            style: const TextStyle(color: AppColors.textBody, fontSize: 13),
          ),
        ]),
      ),
      action: SnackBarAction(
        label: 'Detalles',
        textColor: AppColors.primary,
        onPressed: () => _showDetail(context, title, friendly, error),
      ),
    ),
  );
}

void _showDetail(
  BuildContext context,
  String title,
  String friendly,
  Object error,
) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(friendly,
                style: const TextStyle(
                    color: AppColors.textBody, fontSize: 14, height: 1.4)),
            const SizedBox(height: 14),
            const Text('Detalle técnico',
                style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('$error',
                style: const TextStyle(
                    color: AppColors.textFaint, fontSize: 11, height: 1.4)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cerrar', style: TextStyle(color: AppColors.primary)),
        ),
      ],
    ),
  );
}
