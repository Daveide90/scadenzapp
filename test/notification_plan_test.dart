import 'package:flutter_test/flutter_test.dart';
import 'package:scadenzapp/models/medicine.dart';
import 'package:scadenzapp/services/notification_plan.dart';

Medicine med(String name, DateTime expiry, {int id = 1}) => Medicine(
      id: id,
      cabinetId: 1,
      name: name,
      expirationDate: expiry,
    );

void main() {
  final now = DateTime(2026, 11, 3, 12);

  test('due farmaci con la stessa scadenza: un avviso per giorno, non per '
      'confezione', () {
    final plan = planNotifications([
      med('TACHIPIRINA', DateTime(2027, 1, 31), id: 1),
      med('MOMENT', DateTime(2027, 1, 31), id: 2),
    ], now: now);
    expect(plan.length, 3); // 30 giorni prima, 7 giorni prima, il giorno
    final lastDay = plan.firstWhere((p) => p.when == DateTime(2027, 1, 31, 8));
    expect(lastDay.body, contains('TACHIPIRINA'));
    expect(lastDay.body, contains('MOMENT'));
  });

  test('il giorno della scadenza dice che è l\'ultimo giorno di validità', () {
    final plan = planNotifications([med('AULIN', DateTime(2026, 12, 31))],
        now: now);
    final day = plan.firstWhere((p) => p.when == DateTime(2026, 12, 31, 8));
    expect(day.body, contains('ultimo giorno di validità'));
    expect(day.body, isNot(contains('SCADUTO')));
  });

  test('avvisi di tipo diverso nello stesso giorno finiscono insieme', () {
    final plan = planNotifications([
      med('A', DateTime(2027, 2, 10), id: 1), // scade il 10/2
      med('B', DateTime(2027, 2, 17), id: 2), // 7 giorni prima = 10/2
    ], now: now);
    final day = plan.where((p) => p.when == DateTime(2027, 2, 10, 8)).toList();
    expect(day.length, 1);
    expect(day.single.body, contains('A'));
    expect(day.single.body, contains('B'));
    expect(day.single.title, contains('2 farmaci'));
  });

  test('gli avvisi già passati non si programmano', () {
    // Scade tra 10 giorni: l'avviso dei 30 giorni prima è già passato.
    final plan = planNotifications([med('X', DateTime(2026, 11, 13))],
        now: now);
    expect(plan.map((p) => p.when), [
      DateTime(2026, 11, 6, 8),
      DateTime(2026, 11, 13, 8),
    ]);
  });

  test('identificativo = giorno (AAAAMMGG), unico per giorno', () {
    final plan = planNotifications([med('X', DateTime(2027, 3, 31))],
        now: now);
    expect(plan.map((p) => p.id).toSet().length, plan.length);
    expect(plan.last.id, 20270331);
  });

  test('con moltissime confezioni resta sotto il tetto di Android e tiene '
      'le più vicine', () {
    final meds = [
      for (var i = 0; i < 600; i++)
        med('F$i', DateTime(2027, 1, 1).add(Duration(days: i)), id: i + 1),
    ];
    final plan = planNotifications(meds, now: now);
    expect(plan.length, lessThanOrEqualTo(maxScheduledNotifications));
    expect(maxScheduledNotifications, lessThan(500));
    final sorted = [...plan]..sort((a, b) => a.when.compareTo(b.when));
    expect(plan.map((p) => p.when), sorted.map((p) => p.when));
    expect(plan.first.when, DateTime(2026, 12, 2, 8)); // 30 giorni prima di F0
  });
}
