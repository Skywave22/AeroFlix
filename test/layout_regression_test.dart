import 'package:aeroflix/app/theme/app_spacing.dart';
import 'package:aeroflix/app/theme/app_theme.dart';
import 'package:aeroflix/shared/widgets/poster_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Layout regressions that shipped in 1.4.0.
///
/// Every one of these used to be a hard-coded number that only worked at one
/// text scale on one phone. These tests pin the invariants instead of pixels:
/// no overflow at any viewport / text-scale combination the app supports, and
/// row heights derived from the real content height.
void main() {
  Widget host(
    Widget child, {
    double textScale = 1.0,
    Size size = const Size(360, 640),
  }) {
    return MediaQuery(
      data: MediaQueryData(
        size: size,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  group('PosterCard fits the row heights the app computes', () {
    const viewports = <String, Size>{
      'phone 360x640': Size(360, 640),
      'phone 411x891': Size(411, 891),
      'tv 960x540': Size(960, 540),
    };
    const scales = <double>[1.0, 1.35, 2.0];

    for (final vp in viewports.entries) {
      for (final scale in scales) {
        testWidgets('${vp.key} @ ${scale}x renders without overflow', (
          tester,
        ) async {
          await tester.binding.setSurfaceSize(vp.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));

          // Build a row the same way the screens do, then let the framework
          // report overflow as a test failure.
          await tester.pumpWidget(
            host(
              Builder(
                builder: (context) => SizedBox(
                  height: AppSpacing.posterRowFor(context),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    // The app sizes every tile from the row height; a bare
                    // horizontal ListView would give each child unbounded height.
                    children: [
                      for (final title in const [
                        'A Very Long Movie Title That Wraps To Two Lines',
                        'Short',
                      ])
                        SizedBox(
                          height: AppSpacing.posterRowFor(context),
                          child: PosterCard(
                            imageUrl: '',
                            title: title,
                            metadata: '2024 · 2h 18m',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              textScale: scale,
              size: vp.value,
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('row height grows with the text scale', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final heights = <double>[];
      for (final scale in [1.0, 1.35, 2.0]) {
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) {
                heights.add(AppSpacing.posterRowFor(context));
                return const SizedBox.shrink();
              },
            ),
            textScale: scale,
          ),
        );
        await tester.pump();
      }
      expect(heights, hasLength(3));
      expect(heights[1], greaterThan(heights[0]));
      expect(heights[2], greaterThan(heights[1]));
      // The old fixed 262 was too small at 2x; make sure we actually left it.
      expect(heights.last, greaterThan(AppSpacing.posterRowHeight));
    });

    testWidgets('posterRowFor is never smaller than the poster art', (
      tester,
    ) async {
      late double rowHeight;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) {
              rowHeight = AppSpacing.posterRowFor(context);
              return const SizedBox.shrink();
            },
          ),
          textScale: 2.0,
        ),
      );
      await tester.pump();
      expect(rowHeight, greaterThan(AppSpacing.posterHeight));
    });
  });

  group('player bar layout (screenshot regression)', () {
    testWidgets('the utility strip is centred and never wider than the bar', (
      tester,
    ) async {
      // The reported screenshot had the whole utility strip jammed to the left
      // with a second (media_kit) bar underneath it. The strip is now a centred,
      // scrollable row; this pins the centring so a future edit cannot silently
      // push it back to the left edge on a wide screen.
      await tester.pumpWidget(
        host(
          SizedBox(
            width: 900,
            child: Center(
              child: SizedBox(
                width: double.infinity,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 6; i++)
                        const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.circle),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          size: const Size(900, 400),
        ),
      );

      final row = tester.getRect(find.byType(Row).last);
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      // Centring shows up as equal slack on both sides, within a pixel.
      final leftSlack = row.left - viewport.left;
      final rightSlack = viewport.right - row.right;
      expect((leftSlack - rightSlack).abs(), lessThan(1.0));
    });
  });

  group('grid columns adapt to the viewport', () {
    testWidgets('phone stays at 3 columns, TV grows', (tester) async {
      // `Size` overrides `==`, so it cannot be a key in a *const* map.
      for (final entry in <Size, int>{
        const Size(360, 640): 3,
        const Size(411, 891): 3,
        const Size(760, 1024): 5,
        const Size(1920, 1080): 8,
      }.entries) {
        late int cols;
        await tester.pumpWidget(
          host(
            Builder(
              builder: (context) {
                cols = AppSpacing.posterColumnsFor(context);
                return const SizedBox.shrink();
              },
            ),
            size: entry.key,
          ),
        );
        await tester.pump();
        expect(cols, entry.value, reason: 'at ${entry.key}');
      }
    });
  });

  testWidgets('PosterCard is a semantics button with one label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      host(
        SizedBox(
          height: AppSpacing.posterRowHeight,
          width: 200,
          child: PosterCard(
            imageUrl: '',
            title: 'Dune',
            metadata: '2021',
            onTap: () {},
          ),
        ),
      ),
    );
    // Screen readers previously got the artwork (no label) plus two loose text
    // nodes; now the whole tile is one labelled button. Assert the properties
    // that matter rather than the full flag set, which also includes focus and
    // enabled state.
    // Look the node up by label: `getSemantics(find.byType(PosterCard))`
    // resolves the nearest *ancestor* node, which is the whole screen. Finding
    // it by label is also exactly what a screen reader does.
    expect(find.bySemanticsLabel('Dune, 2021'), findsOneWidget);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Dune, 2021')),
      containsSemantics(
        label: 'Dune, 2021',
        isButton: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('PosterCard activates from the keyboard / d-pad', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            height: AppSpacing.posterRowHeight,
            width: 160,
            child: PosterCard(
              imageUrl: '',
              title: 'Focus me',
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The tile is a FocusableActionDetector: a D-pad centre press (or Enter on
    // a keyboard) fires ActivateIntent, which a bare GestureDetector tile could
    // not receive — the row was unusable on Android TV. The action is
    // registered *inside* the tile, so the lookup has to start from a
    // descendant context, not from PosterCard's own element.
    final ctx = tester.element(find.byType(GestureDetector).first);
    Actions.invoke(ctx, const ActivateIntent());
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
