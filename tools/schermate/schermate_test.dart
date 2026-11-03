// Genera le schermate per il README e per la scheda di Google Play, dai
// widget veri dell'app, con dati inventati (principi attivi, mai marchi, e
// nessun dato di persone reali). Niente emulatore e niente telefono.
//
//   flutter test tools/schermate/schermate_test.dart --update-goldens
//
// Escono in tools/schermate/png/, 1080×1920 (9:16, come chiede Google Play).
// Sta fuori da test/ perché non è una prova: `flutter test` non lo lancia.
// Usa gli agganci per i test (dati finti, database in memoria) come un test.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:scadenzapp/database/database_helper.dart';
import 'package:scadenzapp/providers/cabinet_provider.dart';
import 'package:scadenzapp/providers/medicine_provider.dart';
import 'package:scadenzapp/screens/cabinet_screen.dart';
import 'package:scadenzapp/screens/checks_screen.dart';
import 'package:scadenzapp/screens/home_screen.dart';
import 'package:scadenzapp/screens/restock_screen.dart';
import 'package:scadenzapp/screens/search_screen.dart';
import 'package:scadenzapp/screens/settings_screen.dart';
import 'package:scadenzapp/services/app_lock.dart';
import 'package:scadenzapp/theme/app_theme.dart';
import 'package:scadenzapp/widgets/confirm_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final _now = DateTime.now();
String _day(int days) {
  final d = DateTime(_now.year, _now.month, _now.day + days);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// La cartella dell'SDK di Flutter: FLUTTER_ROOT se c'è, altrimenti risalendo
/// da flutter_tester, che sta in <sdk>/bin/cache/artifacts/engine/<piattaforma>/.
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    if (Directory('${dir.path}/bin/cache/artifacts/material_fonts').existsSync()) {
      return dir.path;
    }
    dir = dir.parent;
  }
  throw StateError('SDK di Flutter non trovato: impostare FLUTTER_ROOT');
}

Future<void> _loadFonts() async {
  final root = _flutterRoot();
  final dir = '$root/bin/cache/artifacts/material_fonts';
  Future<ByteData> f(String name) async =>
      ByteData.sublistView(File('$dir/$name').readAsBytesSync());
  await (FontLoader('Roboto')
        ..addFont(f('Roboto-Regular.ttf'))
        ..addFont(f('Roboto-Medium.ttf'))
        ..addFont(f('Roboto-Bold.ttf'))
        ..addFont(f('Roboto-Italic.ttf')))
      .load();
  await (FontLoader('MaterialIcons')..addFont(f('MaterialIcons-Regular.otf')))
      .load();
}

/// Armadietti e farmaci di un reparto inventato.
Future<Database> _seed() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 4,
      onCreate: DatabaseHelper.createSchema,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      singleInstance: false,
    ),
  );
  final ids = (await db.query('cabinets', orderBy: 'position'))
      .map((r) => r['id'] as int)
      .toList();
  const names = [
    'Carrello emergenze',
    'Armadio farmaci reparto',
    'Frigo farmaci 2-8 °C',
    'Ambulatorio medicazioni',
  ];
  for (var i = 0; i < 4; i++) {
    await db.update('cabinets', {'name': names[i]},
        where: 'id = ?', whereArgs: [ids[i]]);
  }
  Future<void> med(int cab, String name, int days, int qty,
          {String? form, String? dosage, String? lot}) =>
      db.insert('medicines', {
        'cabinet_id': ids[cab],
        'name': name,
        'expiration_date': _day(days),
        'quantity': qty,
        'added_at': _now.toIso8601String(),
        'form': form,
        'dosage': dosage,
        'lot': lot,
      });
  // Carrello emergenze
  await med(0, 'Adrenalina 1 mg/ml', 18, 10, form: 'fiale', lot: 'L24A117');
  await med(0, 'Atropina 0,5 mg/ml', 95, 6, form: 'fiale', lot: 'AT3309');
  await med(0, 'Amiodarone 150 mg/3 ml', 410, 6, form: 'fiale', lot: 'AM8812');
  await med(0, 'Glucosio 33%', -4, 5, form: 'fiale', lot: 'G1020');
  await med(0, 'Naloxone 0,4 mg/ml', 62, 4, form: 'fiale', lot: 'NX4471');
  await med(0, 'Salbutamolo 100 mcg', 230, 2, form: 'spray', lot: 'SB0915');
  await med(0, 'Metilprednisolone 40 mg', 44, 4, form: 'fiale', lot: 'MP2290');
  await med(0, 'Midazolam 5 mg/ml', 300, 5, form: 'fiale', lot: 'MZ5530');
  // Armadio farmaci reparto
  await med(1, 'Paracetamolo 500 mg', 320, 3, form: 'compresse', lot: 'P5521');
  await med(1, 'Adrenalina 1 mg/ml', 18, 2, form: 'fiale', lot: 'L24A117');
  await med(1, 'Ibuprofene 400 mg', 26, 2, form: 'compresse', lot: 'IB7713');
  await med(1, 'Omeprazolo 20 mg', 540, 4, form: 'capsule', lot: 'OM1188');
  await med(1, 'Furosemide 25 mg', 72, 2, form: 'compresse', lot: 'FU3341');
  await med(1, 'Enoxaparina 4000 UI', 14, 10, form: 'siringhe', lot: 'EN0921');
  await med(1, 'Ketorolac 30 mg', -2, 6, form: 'fiale', lot: 'KT6604');
  await med(1, 'Amoxicillina e acido clavulanico 875 mg + 125 mg', 120, 2,
      form: 'compresse', lot: 'AC2207');
  // Frigo
  await med(2, 'Insulina rapida 100 UI/ml', 38, 3, form: 'penne', lot: 'IR4410');
  await med(2, 'Insulina glargine 100 UI/ml', 84, 2, form: 'penne', lot: 'IG0712');
  await med(2, 'Vaccino antinfluenzale', 150, 10, form: 'siringhe', lot: 'VF2611');
  // Ambulatorio
  await med(3, 'Lidocaina 2%', 250, 5, form: 'fiale', lot: 'LD1205');
  await med(3, 'Adrenalina 1 mg/ml', 18, 1, form: 'fiale', lot: 'L24A117');
  await med(3, 'Clorexidina 2%', 17, 3, form: 'soluzione', lot: 'CX0811');
  await med(3, 'Iodopovidone 10%', 200, 2, form: 'soluzione', lot: 'IP4402');

  Future<void> check(int cab, int daysAgo, String who, int checked, int exp,
          int expiring, int removed) =>
      db.insert('cabinet_checks', {
        'cabinet_id': ids[cab],
        'performed_at':
            _now.subtract(Duration(days: daysAgo, hours: 2)).toIso8601String(),
        'operator': who,
        'checked_count': checked,
        'expired_found': exp,
        'expiring_found': expiring,
        'removed_count': removed,
      });
  await check(0, 1, 'Ștefania Popescu', 8, 1, 2, 1);
  await check(1, 2, 'Marco Rinaldi', 7, 1, 2, 1);
  await check(2, 2, 'Giulia Ferri', 3, 0, 1, 0);
  await check(3, 1, 'Luca Marini', 4, 0, 1, 0);
  return db;
}

/// Le chiamate al database girano su un altro isolate: si lascia correre il
/// tempo vero e si ridisegna, finché la schermata è ferma.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pumpAndSettle();
}

/// Sul telefono i testi senza carattere indicato usano Roboto; nell'ambiente
/// di prova uscirebbero come rettangoli. Qui lo si indica.
ThemeData _theme() {
  final t = buildAppTheme();
  return t.copyWith(
    appBarTheme: t.appBarTheme.copyWith(
      titleTextStyle:
          t.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'Roboto'),
    ),
  );
}

/// La schermata della scansione con la fotocamera sostituita da un fondo
/// scuro: nei test la fotocamera non c'è. Il foglio di conferma è quello vero.
class _ScanStandIn extends StatelessWidget {
  const _ScanStandIn();

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text('Scansiona farmaco'),
          backgroundColor: Colors.black87,
          leading: IconButton(icon: const Icon(Icons.close), onPressed: () {}),
          actions: const [
            Icon(Icons.pause),
            SizedBox(width: 12),
            Icon(Icons.medication, color: Colors.greenAccent, size: 20),
            SizedBox(width: 4),
            Icon(Icons.event_available, color: Colors.greenAccent, size: 20),
            SizedBox(width: 12),
          ],
        ),
        body: Column(
          children: [
            const Expanded(
              child: ColoredBox(
                color: Color(0xFF202124),
                child: Center(
                  child: Icon(Icons.photo_camera_outlined,
                      size: 96, color: Colors.white24),
                ),
              ),
            ),
            ConfirmSheet(
              initialName: 'Adrenalina 1 mg/ml',
              initialDate: DateTime(_now.year, _now.month, _now.day + 18),
              initialLot: 'L24A117',
              onSave: (name, date, quantity,
                  {form, dosage, unit, lot}) {},
            ),
          ],
        ),
      );
}

/// Un telefono con il blocco schermo: le Impostazioni mostrano l'interruttore.
class _FakeUnlock implements DeviceUnlock {
  const _FakeUnlock();

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<bool> authenticate(String reason) async => true;
}

Widget _app(Widget home, CabinetProvider cabinets) => MultiProvider(
      providers: [
        // Nell'app l'elenco degli armadietti lo ha già caricato la home.
        ChangeNotifierProvider.value(value: cabinets),
        ChangeNotifierProxyProvider<CabinetProvider, MedicineProvider>(
          create: (_) => MedicineProvider(),
          update: (_, cabinets, medicines) {
            medicines!.onDataChanged = cabinets.markNeedsReload;
            return medicines;
          },
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme(),
        home: home,
      ),
    );

void main() {
  late Database db;

  setUpAll(_loadFonts);

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'intended_use_ack_v1': 'true',
      'last_backup_export': _now.toIso8601String(),
    });
    db = (await TestWidgetsFlutterBinding.ensureInitialized()
        .runAsync(_seed))!;
    DatabaseHelper().useDatabaseForTests(db);
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.ensureInitialized()
        .runAsync(() => db.close());
  });

  Future<void> shot(WidgetTester tester, String name, Widget home,
      {Future<void> Function()? before}) async {
    debugDisableShadows = false; // ombre vere, come sul telefono
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final cabinets = CabinetProvider();
    await tester.runAsync(cabinets.loadCabinets);
    await tester.pumpWidget(_app(home, cabinets));
    await _settle(tester);
    if (before != null) {
      await before();
      await _settle(tester);
    }
    await expectLater(
        find.byType(MaterialApp), matchesGoldenFile('png/$name.png'));
    debugDisableShadows = true;
  }

  testWidgets('01 armadietti', (tester) async {
    await shot(tester, '01_armadietti', const HomeScreen());
  });

  testWidgets('02 carrello emergenze', (tester) async {
    final cab = (await tester.runAsync(() => DatabaseHelper().getCabinets()))!
        .first;
    await shot(tester, '02_armadietto', CabinetScreen(cabinet: cab));
  });

  testWidgets('03 reintegro', (tester) async {
    await shot(tester, '03_reintegro', const RestockScreen());
  });

  testWidgets('04 ricerca per lotto', (tester) async {
    await shot(tester, '04_ricerca_lotto', const SearchScreen(), before: () async {
      await tester.enterText(find.byType(TextField), 'L24A117');
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  testWidgets('05 controlli', (tester) async {
    await shot(tester, '05_controlli', const ChecksScreen());
  });

  testWidgets('06 scansione, conferma di quello che è stato letto',
      (tester) async {
    await shot(tester, '06_scansione_conferma', const _ScanStandIn());
  });

  testWidgets('07 impostazioni', (tester) async {
    await shot(tester, '07_impostazioni',
        const SettingsScreen(deviceUnlock: _FakeUnlock()));
  });

  testWidgets('08 prima di iniziare, al primo avvio', (tester) async {
    FlutterSecureStorage.setMockInitialValues({
      'last_backup_export': _now.toIso8601String(),
    });
    await shot(tester, '08_prima_di_iniziare', const HomeScreen());
  });

  testWidgets('09 promemoria del backup', (tester) async {
    FlutterSecureStorage.setMockInitialValues({'intended_use_ack_v1': 'true'});
    await shot(tester, '09_promemoria_backup', const HomeScreen());
  });
}
