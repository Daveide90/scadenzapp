import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/services/temp_files.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('scadenzapp_test'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File writeFile(String name, {Duration? age}) {
    final f = File('${dir.path}/$name')..writeAsStringSync('x');
    if (age != null) f.setLastModifiedSync(DateTime.now().subtract(age));
    return f;
  }

  test('cancella i PDF più vecchi della soglia', () async {
    final vecchio = writeFile('Controlli_2026-06.pdf', age: const Duration(days: 2));
    final recente = writeFile('Controlli_2026-08.pdf');

    await TempFiles.purgeOldPdfs(dir);

    expect(vecchio.existsSync(), isFalse);
    expect(recente.existsSync(), isTrue);
  });

  test('non tocca i file che non sono PDF', () async {
    final altro = writeFile('backup.bak', age: const Duration(days: 30));

    await TempFiles.purgeOldPdfs(dir);

    expect(altro.existsSync(), isTrue);
  });

  test('la soglia è configurabile', () async {
    final f = writeFile('Reintegro.pdf', age: const Duration(minutes: 30));

    await TempFiles.purgeOldPdfs(dir, maxAge: const Duration(minutes: 10));

    expect(f.existsSync(), isFalse);
  });

  test('una cartella inesistente non solleva errori', () async {
    final assente = Directory('${dir.path}/mai_creata');
    await expectLater(TempFiles.purgeOldPdfs(assente), completes);
  });
}
