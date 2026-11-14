import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aeroflix/app/theme/app_colors.dart';

void main() {
  test('Design tokens are defined', () {
    // ignore: deprecated_member_use_from_same_package
    expect(AppColors.accent.value, isNonZero);
    // ignore: deprecated_member_use_from_same_package
    expect(AppColors.background.value, isNonZero);
  });

  testWidgets('AeroFlix smoke test: MaterialApp renders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('AeroFlix'))),
    ));
    expect(find.text('AeroFlix'), findsOneWidget);
  });
}
