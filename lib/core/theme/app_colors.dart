import 'package:flutter/material.dart';

/// Brutus Mobile — Clean, modern color palette
/// Inspired by Linear, Notion, and Apple Health
class AppColors {
  AppColors._();

  // ── Primary — Warm Indigo ──
  static const primary = Color(0xFF4F46E5);
  static const primaryLight = Color(0xFF818CF8);
  static const primaryDark = Color(0xFF3730A3);
  static const primarySurface = Color(0xFFEEF2FF);

  // ── Surfaces ──
  static const background = Color(0xFFFAFAFB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceVariant = Color(0xFFF4F4F5);
  static const surfaceMuted = Color(0xFFF9FAFB);
  static const cardElevated = Color(0xFFFFFFFF);

  // ── Text ──
  static const textPrimary = Color(0xFF18181B);
  static const textSecondary = Color(0xFF71717A);
  static const textTertiary = Color(0xFFA1A1AA);
  static const textOnPrimary = Color(0xFFFFFFFF);

  // ── Borders ──
  static const border = Color(0xFFE4E4E7);
  static const borderLight = Color(0xFFF4F4F5);
  static const borderFocus = Color(0xFF818CF8);

  // ── Accents ──
  static const success = Color(0xFF10B981);
  static const successLight = Color(0xFFD1FAE5);
  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);
  static const error = Color(0xFFEF4444);
  static const errorLight = Color(0xFFFEE2E2);
  static const info = Color(0xFF3B82F6);
  static const infoLight = Color(0xFFDBEAFE);

  // ── Feature accents ──
  static const email = Color(0xFFEA4335);
  static const weather = Color(0xFF0EA5E9);
  static const stocks = Color(0xFF10B981);
  static const notes = Color(0xFFF59E0B);
  static const maps = Color(0xFF6366F1);
  static const automation = Color(0xFF8B5CF6);
  static const research = Color(0xFFEC4899);
  static const files = Color(0xFF14B8A6);
  static const voice = Color(0xFF4F46E5);

  // ── Gradients ──
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
  );

  static const subtleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFF8F9FF), Color(0xFFF0EEFF)],
  );

  static const warmGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFF7ED), Color(0xFFFEF3F2)],
  );

  static const coolGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFEFF6FF), Color(0xFFEEF2FF)],
  );

  // ── Shadow ──
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF18181B).withValues(alpha: 0.04),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
    BoxShadow(
      color: const Color(0xFF18181B).withValues(alpha: 0.02),
      blurRadius: 4,
      offset: const Offset(0, 1),
    ),
  ];

  static List<BoxShadow> get elevatedShadow => [
    BoxShadow(
      color: const Color(0xFF18181B).withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
    BoxShadow(
      color: const Color(0xFF18181B).withValues(alpha: 0.04),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];

  static List<BoxShadow> get primaryGlow => [
    BoxShadow(
      color: primary.withValues(alpha: 0.25),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];
}
