import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/screens/lock_screen.dart';
import 'package:scadenzapp/screens/settings_screen.dart';
import 'package:scadenzapp/services/app_lock.dart';
import 'package:scadenzapp/services/settings_service.dart';

class FakeUnlock implements DeviceUnlock {
  FakeUnlock({this.available = true, this.result = true});

  bool available;
  bool result;
  int calls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate(String reason) async {
    calls++;
    return result;
  }
}

/// App minima con il blocco attorno al Navigator, come in main.dart.
Widget app(FakeUnlock unlock, {DateTime Function()? now}) => MaterialApp(
      builder: (context, child) => LockScreen(
        deviceUnlock: unlock,
        now: now ?? DateTime.now,
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const Text('HOME'),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const Scaffold(body: Text('ARMADIETTO'))),
              ),
              child: const Text('apri'),
            ),
          ]),
        ),
      ),
    );

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    AppLock.enabled.value = true;
  });

  group('LockScreen', () {
    testWidgets('blocco spento: l\'app si apre senza chiedere niente',
        (tester) async {
      AppLock.enabled.value = false;
      final unlock = FakeUnlock();
      await tester.pumpWidget(app(unlock));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(unlock.calls, 0);
    });

    testWidgets('blocco acceso: sblocco riuscito apre l\'app', (tester) async {
      final unlock = FakeUnlock();
      await tester.pumpWidget(app(unlock));
      await tester.pumpAndSettle();
      expect(unlock.calls, 1);
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('Sblocca per accedere'), findsNothing);
    });

    testWidgets('sblocco annullato: resta il blocco e l\'app non si vede',
        (tester) async {
      final unlock = FakeUnlock(result: false);
      await tester.pumpWidget(app(unlock));
      await tester.pumpAndSettle();
      expect(find.text('Sblocca per accedere'), findsOneWidget);
      expect(find.text('HOME'), findsNothing);

      unlock.result = true;
      await tester.tap(find.text('Sblocca'));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('telefono senza blocco: l\'app si apre senza chiedere',
        (tester) async {
      final unlock = FakeUnlock(available: false);
      await tester.pumpWidget(app(unlock));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(unlock.calls, 0);
    });

    testWidgets(
        'dopo 2 minuti fuori dall\'app il blocco copre anche la schermata '
        'aperta sopra la home, e allo sblocco si torna lì', (tester) async {
      var clock = DateTime(2026, 11, 3, 10);
      final unlock = FakeUnlock();
      await tester.pumpWidget(app(unlock, now: () => clock));
      await tester.pumpAndSettle();
      await tester.tap(find.text('apri'));
      await tester.pumpAndSettle();
      expect(find.text('ARMADIETTO'), findsOneWidget);

      unlock.result = false; // al ritorno l'utente annulla lo sblocco
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = clock.add(const Duration(minutes: 3));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('ARMADIETTO'), findsNothing);
      expect(find.text('Sblocca per accedere'), findsOneWidget);

      unlock.result = true;
      await tester.tap(find.text('Sblocca'));
      await tester.pumpAndSettle();
      expect(find.text('ARMADIETTO'), findsOneWidget);
    });

    testWidgets('meno di 2 minuti fuori dall\'app: niente blocco',
        (tester) async {
      var clock = DateTime(2026, 11, 3, 10);
      final unlock = FakeUnlock();
      await tester.pumpWidget(app(unlock, now: () => clock));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = clock.add(const Duration(seconds: 90));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(unlock.calls, 1);
    });
  });

  group('Impostazioni', () {
    Future<void> openSettings(WidgetTester tester, FakeUnlock unlock) async {
      await tester.pumpWidget(
          MaterialApp(home: SettingsScreen(deviceUnlock: unlock)));
      await tester.pumpAndSettle();
    }

    testWidgets('spegnere il blocco chiede lo sblocco e salva la scelta',
        (tester) async {
      final unlock = FakeUnlock();
      await openSettings(tester, unlock);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(unlock.calls, 1);
      expect(AppLock.enabled.value, isFalse);
      expect(await SettingsService().getAppLockEnabled(), isFalse);
      expect(find.text('Blocco disattivato'), findsOneWidget);
    });

    testWidgets('sblocco annullato: la scelta non cambia', (tester) async {
      final unlock = FakeUnlock(result: false);
      await openSettings(tester, unlock);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(AppLock.enabled.value, isTrue);
      expect(await SettingsService().getAppLockEnabled(), isTrue);
    });

    testWidgets('telefono senza blocco: non si può accendere', (tester) async {
      AppLock.enabled.value = false;
      final unlock = FakeUnlock(available: false);
      await openSettings(tester, unlock);
      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.onChanged, isNull);
      expect(find.textContaining('non ha un PIN'), findsOneWidget);
    });

    testWidgets('telefono senza blocco: spegnerlo non chiede lo sblocco',
        (tester) async {
      final unlock = FakeUnlock(available: false);
      await openSettings(tester, unlock);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(unlock.calls, 0);
      expect(AppLock.enabled.value, isFalse);
    });
  });

  test('di serie il blocco è acceso', () async {
    expect(await SettingsService().getAppLockEnabled(), isTrue);
    await AppLock.load();
    expect(AppLock.enabled.value, isTrue);
  });
}
