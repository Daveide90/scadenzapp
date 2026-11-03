import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/database/database_helper.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('scadenzapp_db_'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('il database che non si apre viene messo da parte, non cancellato',
      () async {
    final path = '${dir.path}/scadenzapp.db';
    File(path).writeAsStringSync('dati cifrati');
    File('$path-wal').writeAsStringSync('wal');
    File('$path-journal').writeAsStringSync('journal');

    final aside = await DatabaseHelper.setAsideDbFiles(
        path, DateTime(2026, 11, 3, 14, 5, 9));

    expect(aside, '$path.non-leggibile-20261103-140509');
    expect(File(path).existsSync(), isFalse);
    expect(File(aside!).readAsStringSync(), 'dati cifrati');
    expect(File('$aside-wal').readAsStringSync(), 'wal');
    expect(File('$aside-journal').readAsStringSync(), 'journal');
  });

  test('senza file non c\'è niente da mettere da parte', () async {
    final aside = await DatabaseHelper.setAsideDbFiles(
        '${dir.path}/scadenzapp.db', DateTime(2026, 11, 3));
    expect(aside, isNull);
  });
}
