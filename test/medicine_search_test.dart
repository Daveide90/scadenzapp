import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/database/database_helper.dart';
import 'package:scadenzapp/models/medicine.dart';
import 'package:scadenzapp/screens/search_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<Database> openTestDb() async {
  sqfliteFfiInit();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: DatabaseHelper.createSchema,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      singleInstance: false,
    ),
  );
}

void main() {
  group('ricerca nel database', () {
    late Database db;

    setUp(() async {
      db = await openTestDb();
      final a = (await db.query('cabinets', orderBy: 'position')).first['id']
          as int;
      final b = await db.insert('cabinets',
          {'name': 'Carrello emergenza', 'position': 9, 'sync_code': 'ZZZZ2345'});
      Future<void> med(int cab, String name, String exp, String? lot) =>
          db.insert('medicines', {
            'cabinet_id': cab,
            'name': name,
            'expiration_date': exp,
            'quantity': 1,
            'added_at': '2026-11-03T10:00:00.000',
            'lot': lot,
          });
      await med(a, 'PARACETAMOLO 500 MG', '2027-05-31', 'A123');
      await med(b, 'Paracetamolo 1000 mg', '2026-12-31', 'B456X');
      await med(b, 'ADRENALINA', '2027-01-31', 'C789');
      await med(a, 'SOLE_100%', '2027-02-28', null);
    });

    tearDown(() => db.close());

    test('trova per nome, senza badare alle maiuscole, in tutti gli armadietti',
        () async {
      final hits = await DatabaseHelper.searchMedicinesIn(db, 'paraceta');
      expect(hits.map((h) => h.medicine.name), [
        'Paracetamolo 1000 mg', // scade prima: in cima
        'PARACETAMOLO 500 MG',
      ]);
      expect(hits.first.cabinetName, 'Carrello emergenza');
    });

    test('trova per lotto, il caso dei ritiri', () async {
      final hits = await DatabaseHelper.searchMedicinesIn(db, 'b456');
      expect(hits.single.medicine.lot, 'B456X');
    });

    test('% e _ si cercano come lettere, non come jolly', () async {
      expect((await DatabaseHelper.searchMedicinesIn(db, '0%')).single
          .medicine.name, 'SOLE_100%');
      expect(await DatabaseHelper.searchMedicinesIn(db, '%%'), isEmpty);
      expect((await DatabaseHelper.searchMedicinesIn(db, 'e_1')).single
          .medicine.name, 'SOLE_100%');
    });

    test('meno di 2 lettere: nessun risultato', () async {
      expect(await DatabaseHelper.searchMedicinesIn(db, ' p '), isEmpty);
    });
  });

  group('schermata di ricerca', () {
    testWidgets('mostra farmaco, armadietto, lotto e scadenza', (tester) async {
      String? asked;
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(
          search: (q) async {
            asked = q;
            return [
              MedicineSearchHit(
                medicine: Medicine(
                  id: 1,
                  cabinetId: 2,
                  name: 'ADRENALINA',
                  expirationDate: DateTime(2027, 1, 31),
                  lot: 'C789',
                ),
                cabinetName: 'Carrello emergenza',
              ),
            ];
          },
        ),
      ));
      await tester.enterText(find.byType(TextField), 'c78');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(asked, 'c78');
      expect(find.text('ADRENALINA'), findsOneWidget);
      expect(find.textContaining('Carrello emergenza'), findsOneWidget);
      expect(find.textContaining('Lotto C789'), findsOneWidget);
      expect(find.textContaining('31/01/2027'), findsOneWidget);
    });

    testWidgets('dice quando non trova niente', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: SearchScreen(search: (_) async => const []),
      ));
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nessun farmaco'), findsOneWidget);
    });
  });
}
