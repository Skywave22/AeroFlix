import 'package:flutter/material.dart';

/// The scrolling utility strip at the bottom of the player.
///
/// Extracted from `player_screen.dart` so the centring behaviour can be
/// tested: it was shipped left-aligned twice, because a bare
/// `SingleChildScrollView` left-aligns its child no matter what the `Row`
/// inside it asks for. The only layout that actually centres *and* still
/// scrolls when the content overflows is `minWidth: viewport` plus a centred
/// `Row`.
class PlayerControlStrip extends StatelessWidget {
  const PlayerControlStrip({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        ),
      ),
    );
  }
}
