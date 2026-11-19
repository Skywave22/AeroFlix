import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AeroFlix smoke test: MaterialApp renders', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(body: Center(child: Text('AeroFlix'))),
    ));
    expect(find.text('AeroFlix'), findsOneWidget);
  });
}
