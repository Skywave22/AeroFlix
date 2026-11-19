import 'package:flutter/material.dart';

class AppRadii {
  AppRadii._();
  static const double sm = 8, md = 12, lg = 14, xl = 18;
  static final BorderRadius smRadius = BorderRadius.circular(sm);
  static final BorderRadius mdRadius = BorderRadius.circular(md);
  static final BorderRadius lgRadius = BorderRadius.circular(lg);
  static final BorderRadius xlRadius = BorderRadius.circular(xl);

  /// Sheets and dialogs all share the top-corner radius below (`xl`), so a
  /// bottom sheet no longer looks like a different component depending on
  /// which screen opened it (14/16/18/20 were all in use).
  static const Radius sheet = Radius.circular(xl);
  static const BorderRadius sheetRadius = BorderRadius.vertical(top: sheet);
}
