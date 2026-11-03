import '../models/medicine.dart';

/// Android tiene al massimo 500 sveglie in attesa per app: oltre, la
/// programmazione fallisce. Si programmano solo i giorni più vicini; gli
/// altri entrano man mano, a ogni riprogrammazione.
const maxScheduledNotifications = 400;

/// Ora dell'avviso.
const _hour = 8;

class PlannedNotification {
  /// Il giorno, AAAAMMGG: un solo avviso per giorno.
  final int id;
  final DateTime when;
  final String title;
  final String body;

  const PlannedNotification({
    required this.id,
    required this.when,
    required this.title,
    required this.body,
  });
}

/// Avvisi da programmare: per ogni confezione 30 giorni prima, 7 giorni
/// prima e il giorno della scadenza, raccolti in **un avviso per giorno**.
/// Solo quelli futuri, i più vicini, al massimo [maxScheduledNotifications].
List<PlannedNotification> planNotifications(
  Iterable<Medicine> medicines, {
  required DateTime now,
}) {
  // giorno → (giorni che mancano alla scadenza → nomi)
  final byDay = <DateTime, Map<int, Set<String>>>{};
  for (final m in medicines) {
    final e = m.expirationDate;
    for (final before in const [30, 7, 0]) {
      final when = DateTime(e.year, e.month, e.day - before, _hour);
      if (!when.isAfter(now)) continue;
      byDay
          .putIfAbsent(when, () => {})
          .putIfAbsent(before, () => <String>{})
          .add(m.name);
    }
  }

  final days = byDay.keys.toList()..sort();
  return [
    for (final when in days.take(maxScheduledNotifications))
      _build(when, byDay[when]!),
  ];
}

PlannedNotification _build(DateTime when, Map<int, Set<String>> groups) {
  final lines = <String>[];
  var count = 0;
  for (final before in const [0, 7, 30]) {
    final names = groups[before];
    if (names == null) continue;
    count += names.length;
    final list = names.join(', ');
    final one = names.length == 1;
    lines.add(switch (before) {
      0 => '${one ? 'Scade' : 'Scadono'} oggi, ultimo giorno di validità: $list',
      7 => '${one ? 'Scade' : 'Scadono'} tra 7 giorni: $list',
      _ => '${one ? 'Scade' : 'Scadono'} tra 30 giorni: $list',
    });
  }
  return PlannedNotification(
    id: when.year * 10000 + when.month * 100 + when.day,
    when: when,
    title: count == 1 ? '1 farmaco da controllare' : '$count farmaci da controllare',
    body: lines.join('\n'),
  );
}
