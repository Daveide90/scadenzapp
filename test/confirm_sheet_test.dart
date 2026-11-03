import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/widgets/confirm_sheet.dart';

Future<GlobalKey<ConfirmSheetState>> pumpSheet(WidgetTester tester) async {
  final key = GlobalKey<ConfirmSheetState>();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ConfirmSheet(
          key: key,
          onSave: (name, date, qty, {form, dosage, unit, lot}) {},
        ),
      ),
    ),
  ));
  return key;
}

void main() {
  testWidgets('la data letta dall\'OCR compila il campo', (tester) async {
    final key = await pumpSheet(tester);
    key.currentState!.updateDate(DateTime(2027, 5, 31));
    await tester.pump();
    expect(find.text('31/05/2027'), findsOneWidget);
  });

  testWidgets(
      'dopo una scelta dell\'utente l\'OCR e il Data Matrix non cambiano più '
      'la data', (tester) async {
    final key = await pumpSheet(tester);
    key.currentState!.updateDate(DateTime(2027, 5, 31)); // OCR, sbagliata
    key.currentState!.setDateByUser(DateTime(2028, 3, 31)); // corretta a mano
    key.currentState!.updateDate(DateTime(2027, 5, 31)); // auto-correzione
    await tester.pump();
    expect(find.text('31/03/2028'), findsOneWidget);
    expect(find.text('31/05/2027'), findsNothing);
  });

  testWidgets('una nuova scelta dell\'utente vale sempre', (tester) async {
    final key = await pumpSheet(tester);
    key.currentState!.setDateByUser(DateTime(2028, 3, 31));
    key.currentState!.setDateByUser(DateTime(2029, 1, 31));
    await tester.pump();
    expect(find.text('31/01/2029'), findsOneWidget);
  });

  testWidgets('reset: la confezione dopo torna a prendere la data dall\'OCR',
      (tester) async {
    final key = await pumpSheet(tester);
    key.currentState!.setDateByUser(DateTime(2028, 3, 31));
    key.currentState!.reset();
    key.currentState!.updateDate(DateTime(2027, 5, 31));
    await tester.pump();
    expect(find.text('31/05/2027'), findsOneWidget);
  });
}
