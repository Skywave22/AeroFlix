import 'package:flutter/material.dart';

class AppColors {
  AppColors._();
  static const Color background = Color(0xFF090A0D);
  static const Color surface = Color(0xFF14161B);
  static const Color surfaceElevated = Color(0xFF20232A);
  static const Color outline = Color(0xFF272A32);
  static const Color textPrimary = Color(0xFFF7F7F8);
  static const Color textSecondary = Color(0xFFA3A6AE);
  static const Color textMuted = Color(0xFF686D78);
  static const Color accent = Color(0xFFE50938);
  static const Color success = Color(0xFF35C98A);
  static const Color error = Color(0xFFF04452);
  static const Color warning = Color(0xFFF5A524);
  static const Color scrimBottom = Color(0xE6090A0D);
  static const Color overlay30 = Color(0x4D000000);
  static const Color overlay50 = Color(0x80000000);
  static const Color overlay70 = Color(0xB3000000);
  static Color accentWithOpacity(double o) => accent.withValues(alpha: o);
  static const LinearGradient heroScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00090A0D), Color(0x66090A0D), scrimBottom],
    stops: [0.0, 0.55, 1.0],
  );
  static const LinearGradient navBarScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00090A0D), Color(0xCC090A0D)],
  );
}
