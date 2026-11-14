import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();
  static TextStyle get _base =>
      GoogleFonts.inter(color: AppColors.textPrimary, letterSpacing: 0);
  static TextStyle get display =>
      _base.copyWith(fontSize: 32, fontWeight: FontWeight.w700, height: 1.15);
  static TextStyle get screenHeading =>
      _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700, height: 1.2);
  static TextStyle get sectionHeading =>
      _base.copyWith(fontSize: 21, fontWeight: FontWeight.w600, height: 1.25);
  static TextStyle get cardTitle =>
      _base.copyWith(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle get body => _base.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.textSecondary);
  static TextStyle get bodyPrimary =>
      body.copyWith(color: AppColors.textPrimary);
  static TextStyle get metadata => _base.copyWith(
      fontSize: 12,
      fontWeight: FontWeight.w400,
      height: 1.35,
      color: AppColors.textSecondary);
  static TextStyle get button =>
      _base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2);
  static TextStyle get appBarTitle =>
      _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle get navLabel =>
      _base.copyWith(fontSize: 11, fontWeight: FontWeight.w500, height: 1.2);
  static TextTheme buildTextTheme() => TextTheme(
        displayLarge: display,
        headlineLarge: screenHeading,
        headlineMedium: sectionHeading,
        titleMedium: cardTitle,
        bodyLarge: bodyPrimary,
        bodyMedium: body,
        bodySmall: metadata,
        labelLarge: button,
        labelSmall: navLabel,
      );
}
