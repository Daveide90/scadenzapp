import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/widgets/notifications_banner.dart';

Widget host(Future<bool> Function() isEnabled, {Future<void> Function()? onEnable}) =>
    MaterialApp(
      home: Scaffold(
        body: NotificationsOffBanner(isEnabled: isEnabled, onEnable: onEnable),
      ),
    );

void main() {
  testWidgets('notifiche spente: l\'avviso c\'è, col pulsante Attiva',
      (tester) async {
    var asked = false;
    await tester.pumpWidget(host(() async => false, onEnable: () async {
      asked = true;
    }));
    await tester.pumpAndSettle();
    expect(find.text('Notifiche spente'), findsOneWidget);
    await tester.tap(find.text('Attiva'));
    await tester.pumpAndSettle();
    expect(asked, isTrue);
  });

  testWidgets('notifiche accese: nessun avviso', (tester) async {
    await tester.pumpWidget(host(() async => true));
    await tester.pumpAndSettle();
    expect(find.text('Notifiche spente'), findsNothing);
  });

  testWidgets('al ritorno nell\'app ricontrolla (il permesso si cambia da '
      'fuori)', (tester) async {
    var enabled = false;
    await tester.pumpWidget(host(() async => enabled));
    await tester.pumpAndSettle();
    expect(find.text('Notifiche spente'), findsOneWidget);

    enabled = true; // acceso dalle impostazioni di Android
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Notifiche spente'), findsNothing);
  });
}
