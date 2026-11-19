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
  static const double posterWidth = 120;
  static const double posterHeight = 180;
  static const double wideCardHeight = 100;

  /// Height of one poster row at 1.0× text scale. Prefer [posterRowFor] where
  /// a [BuildContext] is available.
  static const double posterRowHeight = 262;

  /// Height of a Continue Watching row at 1.0× text scale.
  static const double continueRowHeight = 190;

  /// Poster columns for a grid at the current width: 3 on a phone, more on
  /// tablets and TVs. Every grid used a hard-coded `crossAxisCount: 3`.
  static int posterColumnsFor(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final cols = (w / 132).floor();
    return cols.clamp(3, 8);
  }

  /// Row height for the user's text size.
  ///
  /// The app no longer clamps [MediaQuery.textScaler], so a user at 2× must not
  /// get clipped poster titles: the row grows with the two text lines it holds.
  static double posterRowFor(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final textBlock = (17.0 * 2 + 19.0) * scale;
    return posterHeight + xs + textBlock + 2 + 8;
  }

  /// Same idea for Continue Watching (220 wide 16:9 thumb + two text lines).
  ///
  /// Keep this in sync with `ContinueCard`: thumb (width × 9/16) + [xs] gap +
  /// title line + 2 px gap + metadata line. `ContinueCard` keeps its text in a
  /// [Flexible], so a couple of spare pixels here are harmless while too few
  /// would clip the second line.
  static double continueRowFor(BuildContext context, {double width = 220}) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    return width * 9 / 16 + xs + (18 + 2 + 16) * scale + 2;
  }

  static const EdgeInsets screenHorizontal = EdgeInsets.symmetric(
    horizontal: horizontalPadding,
  );
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}
