import 'package:flutter/material.dart';

class AppSpacing {
  AppSpacing._();
  static const double xxs = 4,
      xs = 8,
      sm = 12,
      md = 16,
      ml = 20,
      lg = 24,
      xl = 32,
      xxl = 40,
      xxxl = 48;
  static const double horizontalPadding = ml;
  static const double sectionGap = xl;
  static const double itemGap = md;
  static const double bottomNavBarHeight = 64;
  static const double posterWidth = 120;
  static const double posterHeight = 180;
  static const double wideCardHeight = 100;
  static const EdgeInsets screenHorizontal =
      EdgeInsets.symmetric(horizontal: horizontalPadding);
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}
