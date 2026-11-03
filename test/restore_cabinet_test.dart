import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/database/database_helper.dart';
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

Map<String, Object?> medicineRow(int cabinetId, String name) => {
      'cabinet_id': cabinetId,
      'name': name,
      'expiration_date': '2027-05-31',
      'quantity': 1,
      'added_at': '2026-11-03T10:00:00.000',
    };

void main() {
  late Database db;
  late int cabinetId;
  late String syncCode;

  setUp(() async {
    db = await openTestDb();
    final first = (await db.query('cabinets', orderBy: 'position')).first;
    cabinetId = first['id'] as int;
    syncCode = first['sync_code'] as String;
    await db.insert('medicines', medicineRow(cabinetId, 'VECCHIO'));
    await db.insert('cabinet_checks', {
      'cabinet_id': cabinetId,
      'performed_at': '2026-10-01T09:00:00.000',
      'operator': 'Rossi',
      'checked_count': 1,
    });
  });

  tearDown(() => db.close());

  test('ripristinare un armadietto non cancella il suo registro dei controlli',
      () async {
    await DatabaseHelper.restoreCabinetInto(db, {
      'cabinets': [
        {'id': 99, 'name': 'Armadietto 1', 'position': 7, 'sync_code': syncCode}
      ],
      'medicines': [medicineRow(99, 'NUOVO')],
    });

    final checks = await db.query('cabinet_checks');
    expect(checks.length, 1);
    expect(checks.single['cabinet_id'], cabinetId);

    final meds = await db.query('medicines', where: 'cabinet_id = ?',
        whereArgs: [cabinetId]);
    expect(meds.map((m) => m['name']), ['NUOVO']);

    final cab = (await db.query('cabinets', where: 'id = ?',
            whereArgs: [cabinetId]))
        .single;
    expect(cab['position'], 0); // resta al suo posto
  });

  test('un armadietto che non c\'era va in fondo, non alla posizione del '
      'backup', () async {
    await DatabaseHelper.restoreCabinetInto(db, {
      'cabinets': [
        {'id': 5, 'name': 'Carrello', 'position': 0, 'sync_code': 'NUOVO-CODICE'}
      ],
      'medicines': [medicineRow(5, 'FIALA')],
    });

    final cabs = await db.query('cabinets', orderBy: 'position');
    expect(cabs.last['name'], 'Carrello');
    expect(cabs.last['position'], 4);
    final medsOfNew = await db.query('medicines',
        where: 'cabinet_id = ?', whereArgs: [cabs.last['id']]);
    expect(medsOfNew.single['name'], 'FIALA');
  });
}
