import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/app_info.dart';
import 'package:scadenzapp/legal/intended_use.dart';
import 'package:scadenzapp/legal/licenses.dart';
import 'package:scadenzapp/screens/settings_screen.dart';
import 'package:scadenzapp/services/app_lock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Unlock implements DeviceUnlock {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> authenticate(String reason) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('versione e catalogo', () {
    test('la versione mostrata è quella di pubspec.yaml', () {
      final line = File('pubspec.yaml')
          .readAsLinesSync()
          .firstWhere((l) => l.startsWith('version:'));
      expect(line.trim(), 'version: $appVersion+$appBuild');
    });

    test('la data del catalogo AIFA è quella dentro il file incluso', () async {
      final tmp = Directory.systemTemp.createTempSync('aifa_');
      final db = File('${tmp.path}/c.db')
        ..writeAsBytesSync(
            gzip.decode(File('assets/aifa_catalog.db.gz').readAsBytesSync()));
      sqfliteFfiInit();
      final con = await databaseFactoryFfi.openDatabase(db.path,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      final rows = await con.query('meta', where: "chiave = 'generato'");
      await con.close();
      tmp.deleteSync(recursive: true);
      expect(rows.single['valore'], aifaCatalogDate);
    });
  });

  group('uso previsto', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    Future<void> pumpHome(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback(
              (_) => showIntendedUseNoticeIfNeeded(context));
          return const Scaffold(body: Text('home'));
        }),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('al primo avvio dice cos\'è e cosa non è', (tester) async {
      await pumpHome(tester);
      expect(find.textContaining(RegExp('non è un dispositivo medico', caseSensitive: false)), findsWidgets);
      expect(find.textContaining('confezione'), findsWidgets);
      await tester.tap(find.text('Ho capito'));
      await tester.pumpAndSettle();
      expect(find.text('Ho capito'), findsNothing);
    });

    testWidgets('dopo «Ho capito» non torna più', (tester) async {
      await pumpHome(tester);
      await tester.tap(find.text('Ho capito'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await pumpHome(tester);
      expect(find.text('Ho capito'), findsNothing);
    });

    test('il testo completo copre i limiti che contano', () {
      final all = intendedUseSections.map((s) => '${s.title} ${s.body}').join(' ');
      for (final must in [
        'dispositivo medico',
        'confezione',
        'AIFA',
        'ritiri',
        'notifiche',
        'backup',
      ]) {
        expect(all, contains(must), reason: must);
      }
    });
  });

  group('impostazioni e licenze', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    testWidgets('informazioni senza email, con versione, avvertenze e licenze',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: SettingsScreen(deviceUnlock: _Unlock())));
      await tester.pumpAndSettle();
      expect(find.text('Uso previsto e avvertenze'), findsOneWidget);
      expect(find.text('Dati dei farmaci'), findsOneWidget);
      expect(find.text('Licenze'), findsOneWidget);
      await tester.tap(find.text('Informazioni su ScadenzApp'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Versione $appVersion'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
    });

    test('le licenze dei componenti Android e dei dati ci sono', () async {
      registerExtraLicenses();
      final packages = <String>{};
      await for (final entry in LicenseRegistry.licenses) {
        packages.addAll(entry.packages);
      }
      for (final p in [
        'SQLCipher',
        'Roboto',
        'Dati dei farmaci (AIFA)',
        'Librerie Android',
        'SLF4J',
      ]) {
        expect(packages, contains(p));
      }
    });
  });
}
