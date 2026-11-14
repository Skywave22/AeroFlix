import 'package:flutter_test/flutter_test.dart';
import 'package:aeroflix/app/app.dart';

void main() {
  testWidgets('AeroFlix boots and shows Home tab', (tester) async {
    await tester.pumpWidget(const AeroFlixApp());
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('AeroFlix'), findsOneWidget);
  });
}
