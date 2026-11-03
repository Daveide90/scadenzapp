import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/services/backup_reminder.dart';
import 'package:scadenzapp/services/settings_service.dart';
import 'package:scadenzapp/widgets/backup_reminder_banner.dart';

void main() {
  final now = DateTime(2026, 11, 3, 10);

  group('quando ricordare il backup', () {
    test('niente farmaci, niente promemoria', () {
      expect(
          BackupReminder.isDue(medicineCount: 0, lastExport: null, now: now),
          isFalse);
    });

    test('farmaci e nessun backup salvato fuori dall\'app', () {
      expect(
          BackupReminder.isDue(medicineCount: 3, lastExport: null, now: now),
          isTrue);
    });

    test('backup salvato 10 giorni fa: basta', () {
      expect(
          BackupReminder.isDue(
              medicineCount: 3,
              lastExport: now.subtract(const Duration(days: 10)),
              now: now),
          isFalse);
    });

    test('backup salvato 31 giorni fa: va rifatto', () {
      expect(
          BackupReminder.isDue(
              medicineCount: 3,
              lastExport: now.subtract(const Duration(days: 31)),
              now: now),
          isTrue);
    });

    test('«più tardi» lo zittisce fino alla data scelta', () {
      expect(
          BackupReminder.isDue(
              medicineCount: 3,
              lastExport: null,
              snoozedUntil: now.add(const Duration(days: 1)),
              now: now),
          isFalse);
      expect(
          BackupReminder.isDue(
              medicineCount: 3,
              lastExport: null,
              snoozedUntil: now.subtract(const Duration(minutes: 1)),
              now: now),
          isTrue);
    });
  });

  group('impostazioni del promemoria', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    test('ultimo backup salvato e rinvio si conservano', () async {
      final s = SettingsService();
      expect(await s.getLastBackupExport(), isNull);
      await s.setLastBackupExport(now);
      expect(await s.getLastBackupExport(), now);
      await s.setBackupReminderSnoozedUntil(now.add(const Duration(days: 7)));
      expect(await s.getBackupReminderSnoozedUntil(),
          now.add(const Duration(days: 7)));
    });
  });

  group('messaggi d\'errore del backup', () {
    test('i messaggi dell\'app arrivano senza «Exception:»', () {
      expect(
          backupErrorMessage(Exception('Password errata o file corrotto'),
              fallback: 'x'),
          'Password errata o file corrotto');
    });

    test('gli errori tecnici diventano una frase comprensibile', () {
      expect(
          backupErrorMessage(
              const FileSystemException('No space left on device', '/data'),
              fallback: 'Backup non riuscito.'),
          'Backup non riuscito.');
      expect(backupErrorMessage(StateError('boh'), fallback: 'Y'), 'Y');
    });
  });

  group('avviso nella home', () {
    Future<void> pump(WidgetTester tester,
        {required bool due,
        VoidCallback? onBackup,
        Future<void> Function()? onSnooze}) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: BackupReminderBanner(
            medicineCount: 5,
            isDue: (_) async => due,
            lastExport: () async => null,
            onBackup: onBackup ?? () {},
            onSnooze: onSnooze ?? () async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('se il backup serve, lo dice e lo fa fare', (tester) async {
      var asked = false;
      await pump(tester, due: true, onBackup: () => asked = true);
      expect(find.textContaining('fuori dall\'app'), findsOneWidget);
      await tester.tap(find.text('Fai il backup'));
      expect(asked, isTrue);
    });

    testWidgets('«Più tardi» lo nasconde', (tester) async {
      var snoozed = false;
      await pump(tester, due: true, onSnooze: () async => snoozed = true);
      await tester.tap(find.text('Più tardi'));
      await tester.pumpAndSettle();
      expect(snoozed, isTrue);
      expect(find.text('Fai il backup'), findsNothing);
    });

    testWidgets('se non serve, non c\'è', (tester) async {
      await pump(tester, due: false);
      expect(find.text('Fai il backup'), findsNothing);
    });
  });
}
