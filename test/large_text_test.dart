import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/legal/intended_use.dart';
import 'package:scadenzapp/models/medicine.dart';
import 'package:scadenzapp/screens/settings_screen.dart';
import 'package:scadenzapp/services/app_lock.dart';
import 'package:scadenzapp/widgets/backup_reminder_banner.dart';
import 'package:scadenzapp/widgets/medicine_tile.dart';

class _Unlock implements DeviceUnlock {
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<bool> authenticate(String reason) async => true;
}

/// Telefono stretto (360 dp, più stretto di un telefono comune da 372 dp) con i caratteri
/// al 200%, il massimo delle impostazioni di accessibilità di Android.
/// Un testo che esce dai bordi fa fallire il test.
Future<void> pumpLarge(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(360 * 3, 780 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(2)),
      child: c!,
    ),
    home: child,
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('riga del farmaco con nome lungo e lotto', (tester) async {
    await pumpLarge(
      tester,
      Scaffold(
        body: MedicineTile(
          medicine: Medicine(
            id: 1,
            cabinetId: 1,
            name: 'Amoxicillina e acido clavulanico 875 mg + 125 mg',
            expirationDate: DateTime.now().add(const Duration(days: 20)),
            quantity: 12,
            lot: 'AB12345678',
          ),
          onTap: () {},
          onDelete: () {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('avviso del backup', (tester) async {
    await pumpLarge(
      tester,
      Scaffold(
        body: BackupReminderBanner(
          medicineCount: 3,
          isDue: (_) async => true,
          lastExport: () async => null,
          onBackup: () {},
          onSnooze: () async {},
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('impostazioni', (tester) async {
    await pumpLarge(tester, SettingsScreen(deviceUnlock: _Unlock()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('uso previsto e avvertenze', (tester) async {
    await pumpLarge(tester, const IntendedUseScreen());
    expect(tester.takeException(), isNull);
  });
}
