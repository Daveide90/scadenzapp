import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/main.dart';

void main() {
  testWidgets('App launches', (WidgetTester tester) async {
    await tester.pumpWidget(const ScadenzApp());
    expect(find.text('ScadenzApp'), findsOneWidget);
  });
}
