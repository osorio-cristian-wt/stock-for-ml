import 'package:flutter/material.dart';

/// Palette for the "Estilo B · Oscuro / Fintech" direction confirmed in the
/// design (Stock for ML — Vistas). Centralized so screens never hardcode hex.
abstract final class AppColors {
  // Backgrounds.
  static const bg = Color(0xFF0D0F13); // screen background
  static const surface = Color(0xFF161A20); // cards / inputs
  static const surfaceDeep = Color(0xFF0D0F13); // inset wells
  static const frame = Color(0xFF14181E); // bottom sheets

  // Lines.
  static const border = Color(0xFF232A33);
  static const borderStrong = Color(0xFF2F3845);

  // Text.
  static const textPrimary = Color(0xFFEEF2F6);
  static const textSecondary = Color(0xFF9AA6B2);
  static const textBody = Color(0xFFC4CDD6);
  static const textMuted = Color(0xFF6B7684);
  static const textFaint = Color(0xFF5B6573);

  // Brand / semantic.
  static const primary = Color(0xFF10B981); // emerald
  static const onPrimary = Color(0xFF06281D);
  static const warning = Color(0xFFF5A524);
  static const danger = Color(0xFFF87171);
  static const dangerStrong = Color(0xFFEF4444);

  // MercadoLibre yellow (used only for the "Conectar con ML" CTA).
  static const mlYellow = Color(0xFFFFE600);
  static const onMlYellow = Color(0xFF1A1A1A);

  // Tinted surfaces (icon chips / badges).
  static Color primarySoft = primary.withValues(alpha: 0.16);
  static Color warningSoft = warning.withValues(alpha: 0.16);
  static Color dangerSoft = danger.withValues(alpha: 0.18);
}
