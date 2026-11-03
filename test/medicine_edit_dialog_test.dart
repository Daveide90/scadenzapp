import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/models/medicine.dart';
import 'package:scadenzapp/widgets/medicine_edit_dialog.dart';

final _med = Medicine(
  id: 7,
  cabinetId: 3,
  name: 'TACHIPIRINA',
  expirationDate: DateTime(2027, 5, 31),
  quantity: 2,
  dosage: '500 mg',
  lot: 'A123',
  form: 'compresse',
);

/// Apre la finestra e restituisce cosa ha salvato (null = annullata).
Future<Medicine? Function()> open(WidgetTester tester, Medicine m) async {
  Medicine? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => ElevatedButton(
        onPressed: () async =>
            result = await showMedicineEditDialog(context, m),
        child: const Text('apri'),
      ),
    ),
  ));
  await tester.tap(find.text('apri'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  testWidgets('nome, dosaggio e lotto si possono correggere', (tester) async {
    final result = await open(tester, _med);
    expect(find.widgetWithText(TextField, 'A123'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'TACHIPIRINA'),
        'TACHIPIRINA 1000');
    await tester.enterText(find.widgetWithText(TextField, '500 mg'), '1000 mg');
    await tester.enterText(find.widgetWithText(TextField, 'A123'), 'B456');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();

    final saved = result()!;
    expect(saved.id, 7);
    expect(saved.cabinetId, 3);
    expect(saved.name, 'TACHIPIRINA 1000');
    expect(saved.dosage, '1000 mg');
    expect(saved.lot, 'B456');
    expect(saved.form, 'compresse');
    expect(saved.quantity, 2);
    expect(saved.expirationDate, DateTime(2027, 5, 31));
  });

  testWidgets('svuotare il lotto lo cancella davvero', (tester) async {
    final result = await open(tester, _med);
    await tester.enterText(find.widgetWithText(TextField, 'A123'), '');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(result()!.lot, isNull);
  });

  testWidgets('senza nome non si salva', (tester) async {
    final result = await open(tester, _med);
    await tester.enterText(find.widgetWithText(TextField, 'TACHIPIRINA'), ' ');
    await tester.tap(find.text('Salva'));
    await tester.pumpAndSettle();
    expect(find.text('Salva'), findsOneWidget); // la finestra resta aperta
    expect(result(), isNull);
  });

  testWidgets('una scadenza nel 2044 apre il calendario senza errori',
      (tester) async {
    await open(tester, _med.copyWith(expirationDate: DateTime(2044, 12, 31)));
    await tester.tap(find.text('31/12/2044'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });
}
