import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTypography {
  AppTypography._();

  /// No custom font is bundled: naming a family that ships with the app but is
  /// missing from `pubspec.yaml` only hid the fact that every style was being
  /// rendered in the platform default. Until Inter is added as a real asset,
  /// fall back explicitly so the intent is honest and predictable.
  static const String? _fontFamily = null;

  static TextStyle get _base => TextStyle(
        fontFamily: _fontFamily,
        color: AppColors.textPrimary,
        letterSpacing: 0,
        fontFamilyFallback: const ['Roboto', 'sans-serif'],
      );
  static TextStyle get display =>
      _base.copyWith(fontSize: 34, fontWeight: FontWeight.w800, height: 1.12);
  static TextStyle get screenHeading =>
      _base.copyWith(fontSize: 30, fontWeight: FontWeight.w700, height: 1.2);
  static TextStyle get sectionHeading =>
      _base.copyWith(fontSize: 23, fontWeight: FontWeight.w700, height: 1.25);
  static TextStyle get cardTitle =>
      _base.copyWith(fontSize: 17.5, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle get body => _base.copyWith(
      fontSize: 15.5,
      fontWeight: FontWeight.w400,
      height: 1.45,
      color: AppColors.textSecondary);
  static TextStyle get bodyPrimary =>
      body.copyWith(color: AppColors.textPrimary);
  static TextStyle get metadata => _base.copyWith(
      fontSize: 13.5,
      fontWeight: FontWeight.w400,
      height: 1.38,
      color: AppColors.textSecondary);

  /// Smallest legible label. Previously every screen re-invented this with an
  /// ad-hoc `copyWith(fontSize: 10 | 11 | 12)`.
  static TextStyle get micro => _base.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      height: 1.25,
      color: AppColors.textMuted);
  static TextStyle get button =>
      _base.copyWith(fontSize: 16.5, fontWeight: FontWeight.w600, height: 1.2);
  static TextStyle get appBarTitle =>
      _base.copyWith(fontSize: 20, fontWeight: FontWeight.w700, height: 1.25);
  static TextStyle get navLabel =>
      _base.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2);

  /// Small but still legible on a 1080p TV at 3 m.
  static TextStyle get chip =>
      _base.copyWith(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2);
  static TextStyle get caption => _base.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      height: 1.3,
      color: AppColors.textSecondary);
  static TextStyle get heroTitle =>
      _base.copyWith(fontSize: 34, fontWeight: FontWeight.w800, height: 1.1);
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
