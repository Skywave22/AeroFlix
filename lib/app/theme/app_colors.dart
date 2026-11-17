import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const Color background = Color(0xFF06070C);
  static const Color surface = Color(0xFF12141B);
  static const Color surfaceElevated = Color(0xFF1C1F29);
  static const Color outline = Color(0xFF2A2E3A);
  static const Color textPrimary = Color(0xFFF7F7F8);
  static const Color textSecondary = Color(0xFFB4B8C4);
  static const Color textMuted = Color(0xFF7B8093);
  // Brand palette taken from the AeroFlix logo (blue -> violet gradient).
  static const Color accent = Color(0xFF2F7BFF); // primary blue
  static const Color accentAlt = Color(0xFF7B2BF7); // violet end of gradient
  static const Color accentSoft = Color(0xFF6AA5FF);
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF0A84FF), Color(0xFF7B2BF7)],
  );
  static const LinearGradient brandGradientDiagonal = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A84FF), Color(0xFF5B2BF7)],
  );
  static const Color success = Color(0xFF35C98A);
  static const Color error = Color(0xFFF04452);
  static const Color warning = Color(0xFFF5A524);
  static const Color scrimBottom = Color(0xE606070C);
  static const Color overlay30 = Color(0x4D000000);
  static const Color overlay50 = Color(0x80000000);
  static const Color overlay70 = Color(0xB3000000);
  static Color accentWithOpacity(double o) => accent.withValues(alpha: o);
  static const LinearGradient heroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0006070C), Color(0x6606070C), scrimBottom],
    stops: [0.0, 0.55, 1.0],
  );
  static const LinearGradient navBarScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x0006070C), Color(0xE606070C)],
  );
}
