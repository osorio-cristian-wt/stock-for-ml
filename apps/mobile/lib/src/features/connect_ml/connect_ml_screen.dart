import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/queries.dart';
import '../../data/supabase_providers.dart';
import '../../theme/app_colors.dart';

/// Screen 02 · Conectar cuenta ML (OAuth 2.0 + PKCE). The app asks the backend
/// for an authorize URL, opens it in the browser, and then polls `ml_accounts`
/// to detect when the `oauth-callback` function finished linking.
class ConnectMlScreen extends ConsumerStatefulWidget {
  const ConnectMlScreen({super.key, this.standalone = false});

  /// When pushed from Settings we show a back button and pop on success;
  /// when shown as an onboarding gate we offer "Más tarde".
  final bool standalone;

  @override
  ConsumerState<ConnectMlScreen> createState() => _ConnectMlScreenState();
}

class _ConnectMlScreenState extends ConsumerState<ConnectMlScreen> {
  bool _busy = false;
  bool _waiting = false; // browser opened, waiting for the callback
  String? _error;

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final uri = await ref.read(connectionRepositoryProvider).authorizeUrl();
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw StateError('No se pudo abrir el navegador.');
      if (mounted) setState(() => _waiting = true);
    } catch (e) {
      setState(() => _error = _friendly(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recheck() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    ref.invalidate(mlAccountProvider);
    final account = await ref.read(mlAccountProvider.future);
    if (account != null) {
      // Best-effort first import of publications.
      unawaited(ref.read(connectionRepositoryProvider).triggerInitialSync());
      if (!mounted) return;
      if (widget.standalone) {
        Navigator.of(context).pop(true);
      } else {
        ref.read(mlSetupDismissedProvider.notifier).state = true;
      }
      return;
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _error = 'Todavía no vemos la conexión. ¿Completaste la autorización?';
      });
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('Function')) {
      return 'El backend de conexión todavía no está disponible.';
    }
    return 'No se pudo conectar con MercadoLibre.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.standalone
          ? AppBar(title: const Text('Conectar Mercado Libre'))
          : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const _MlBadge(),
                  const SizedBox(height: 24),
                  const Text(
                    'Conectá tu cuenta de\nMercadoLibre',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vamos a importar tus publicaciones, comisiones y ventas. '
                    'Autorizás en el sitio de ML; nosotros nunca vemos tu contraseña.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.5),
                  ),
                  const SizedBox(height: 30),
                  const _Perk('Importar publicaciones activas'),
                  const SizedBox(height: 11),
                  const _Perk('Descontar stock al vender'),
                  const SizedBox(height: 11),
                  const _Perk('Comisiones y rentabilidad reales'),
                  const SizedBox(height: 26),
                  if (_error != null) ...[
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (!_waiting)
                    _YellowButton(
                      label: 'Conectar con Mercado Libre',
                      busy: _busy,
                      onPressed: _busy ? null : _connect,
                    )
                  else
                    Column(
                      children: [
                        const Text(
                          'Autorizá en el navegador y volvés solo. Si no, tocá acá.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy ? null : _recheck,
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: AppColors.onPrimary,
                                  ),
                                )
                              : const Text('Ya autoricé en ML'),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _busy ? null : _connect,
                          child: const Text(
                            'Volver a abrir el navegador',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  const Text(
                    'Conexión segura OAuth 2.0 · PKCE',
                    style: TextStyle(fontSize: 12, color: AppColors.textFaint),
                  ),
                  if (!widget.standalone) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          ref.read(mlSetupDismissedProvider.notifier).state = true,
                      child: const Text(
                        'Más tarde',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MlBadge extends StatelessWidget {
  const _MlBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: AppColors.mlYellow,
              shape: BoxShape.circle,
            ),
          ),
          Positioned(
            bottom: -8,
            right: -8,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 3),
              ),
              child: const Icon(Icons.check, color: AppColors.onPrimary, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

class _Perk extends StatelessWidget {
  const _Perk(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppColors.textBody),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one place we use the MercadoLibre yellow — its branded OAuth CTA.
class _YellowButton extends StatelessWidget {
  const _YellowButton({required this.label, required this.onPressed, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.mlYellow,
          foregroundColor: AppColors.onMlYellow,
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.onMlYellow,
                ),
              )
            : Text(label),
      ),
    );
  }
}
