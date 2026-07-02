import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_colors.dart';
import 'auth_controller.dart';

/// Screen 01 · Login (Supabase Auth). On success the [AuthGate] reacts to the
/// new session and moves the user forward to "Conectar ML".
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _signUp = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Completá email y contraseña.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = ref.read(authControllerProvider);
    try {
      if (_signUp) {
        await auth.signUp(email: email, password: password);
      } else {
        await auth.signIn(email: email, password: password);
      }
      if (_signUp && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Revisá tu email para confirmar.')),
        );
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'No se pudo iniciar sesión. Probá de nuevo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Ingresá tu email para recuperar la contraseña.');
      return;
    }
    try {
      await ref.read(authControllerProvider).resetPassword(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Te enviamos un email de recuperación.')),
        );
      }
    } catch (_) {
      setState(() => _error = 'No se pudo enviar el email.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Logo(),
                  const SizedBox(height: 26),
                  const Text(
                    'Stock for ML',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Tu stock y tu rentabilidad de MercadoLibre, en un solo lugar.',
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted, height: 1.4),
                  ),
                  const SizedBox(height: 34),
                  _Field(
                    label: 'Email',
                    controller: _email,
                    hint: 'camila@minegocio.com',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 14),
                  _Field(
                    label: 'Contraseña',
                    controller: _password,
                    hint: '••••••••••',
                    obscure: _obscure,
                    onSubmitted: (_) => _submit(),
                    suffix: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: const TextStyle(color: AppColors.danger, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: AppColors.onPrimary,
                            ),
                          )
                        : Text(_signUp ? 'Crear cuenta' : 'Ingresar'),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: TextButton(
                      onPressed: _busy ? null : _forgot,
                      child: const Text(
                        '¿Olvidaste tu contraseña?',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _signUp = !_signUp;
                                _error = null;
                              }),
                      child: Text(
                        _signUp
                            ? '¿Ya tenés cuenta? Ingresá'
                            : 'Crear una cuenta nueva',
                        style: const TextStyle(color: AppColors.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Center(
                    child: Text(
                      'Tus credenciales de ML nunca se guardan en el\n'
                      'dispositivo. Todo viaja cifrado.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textFaint,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.4),
            blurRadius: 30,
          ),
        ],
      ),
      child: const Icon(Icons.bar_chart_rounded, color: AppColors.onPrimary, size: 30),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.keyboardType,
    this.suffix,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6, left: 2),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          onSubmitted: onSubmitted,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(hintText: hint, suffixIcon: suffix),
        ),
      ],
    );
  }
}
