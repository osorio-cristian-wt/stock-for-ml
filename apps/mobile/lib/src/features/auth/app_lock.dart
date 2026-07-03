import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart';
import '../../ui/widgets/brand_logo.dart';
import 'auth_controller.dart';

/// Bloqueo biométrico de la sesión: si la app estuvo en segundo plano más de
/// [AppLock.timeout] (o arranca en frío con sesión activa), pide Face ID /
/// huella antes de mostrar el contenido. La sesión de Supabase sigue viva —
/// esto es un candado local para desbloquear rápido sin retipear la clave.
/// Se activa/desactiva en Ajustes; la preferencia vive en el dispositivo.
const _kLockEnabledKey = 'biometric_lock_enabled';

final _prefsProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

/// ¿El candado está activado por el usuario? (default: apagado)
final appLockEnabledProvider = FutureProvider<bool>((ref) async {
  final prefs = await ref.watch(_prefsProvider.future);
  return prefs.getBool(_kLockEnabledKey) ?? false;
});

/// ¿El dispositivo puede autenticar con biometría o credencial local?
final biometricsAvailableProvider = FutureProvider<bool>((ref) async {
  try {
    final auth = LocalAuthentication();
    return await auth.isDeviceSupported();
  } catch (_) {
    return false;
  }
});

/// Cambia la preferencia. Al ACTIVAR exige pasar la biometría una vez (así
/// nadie activa un candado que después no puede abrir).
Future<bool> setAppLockEnabled(WidgetRef ref, bool enabled) async {
  if (enabled) {
    final ok = await _authenticate();
    if (!ok) return false;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kLockEnabledKey, enabled);
  ref.invalidate(appLockEnabledProvider);
  return true;
}

Future<bool> _authenticate() async {
  try {
    final auth = LocalAuthentication();
    return await auth.authenticate(
      localizedReason: 'Desbloqueá Stock for ML',
      options: const AuthenticationOptions(stickyAuth: true),
    );
  } catch (_) {
    return false;
  }
}

/// Envuelve el contenido firmado: observa el ciclo de vida y muestra la
/// pantalla de candado cuando corresponde.
class AppLock extends ConsumerStatefulWidget {
  const AppLock({super.key, required this.child});

  final Widget child;

  /// Tiempo fuera de la app a partir del cual se vuelve a pedir biometría.
  static const timeout = Duration(minutes: 5);

  @override
  ConsumerState<AppLock> createState() => _AppLockState();
}

class _AppLockState extends ConsumerState<AppLock>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _authInProgress = false;
  DateTime? _backgroundedAt;
  bool _coldStartChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final away = _backgroundedAt == null
          ? Duration.zero
          : DateTime.now().difference(_backgroundedAt!);
      _backgroundedAt = null;
      if (away >= AppLock.timeout) _lockIfEnabled();
    }
  }

  Future<void> _lockIfEnabled() async {
    final enabled = await ref.read(appLockEnabledProvider.future);
    if (enabled && mounted && !_locked) {
      setState(() => _locked = true);
      _tryUnlock();
    }
  }

  Future<void> _tryUnlock() async {
    if (_authInProgress) return;
    _authInProgress = true;
    try {
      final ok = await _authenticate();
      if (ok && mounted) setState(() => _locked = false);
    } finally {
      _authInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Arranque en frío con sesión viva: si el candado está activo, pedirlo.
    if (!_coldStartChecked) {
      _coldStartChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _lockIfEnabled());
    }

    return Stack(
      children: [
        widget.child,
        if (_locked)
          Positioned.fill(
            child: _LockScreen(
              onUnlock: _tryUnlock,
              onSignOut: () async {
                await ref.read(authControllerProvider).signOut();
                if (mounted) setState(() => _locked = false);
              },
            ),
          ),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock, required this.onSignOut});

  final VoidCallback onUnlock;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              const BrandLogo(markSize: 56, wordmarkSize: 28),
              const SizedBox(height: 28),
              const Icon(Icons.lock_outline_rounded,
                  size: 34, color: AppColors.textSecondary),
              const SizedBox(height: 10),
              const Text(
                'La app quedó bloqueada por inactividad.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint_rounded, size: 20),
                label: const Text('Desbloquear'),
              ),
              const Spacer(),
              TextButton(
                onPressed: onSignOut,
                child: const Text('Cerrar sesión',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
