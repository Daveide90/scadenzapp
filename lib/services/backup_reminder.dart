import 'package:flutter/foundation.dart';

import 'settings_service.dart';

/// Promemoria del backup salvato FUORI dall'app.
///
/// I backup nascono nella cartella privata dell'app, che Android cancella
/// quando l'app viene disinstallata e che sparisce con un telefono rotto o
/// perso. Il trasferimento automatico fra telefoni è spento (il database
/// cifrato non si aprirebbe senza la sua chiave), quindi il backup salvato
/// fuori è l'unico modo per non perdere i dati.
class BackupReminder {
  const BackupReminder._();

  static const maxAge = Duration(days: 30);
  static const snooze = Duration(days: 7);

  /// Cambia ogni volta che un backup viene salvato fuori o il promemoria
  /// rinviato: l'avviso nella home si ricontrolla.
  static final changed = ValueNotifier<int>(0);

  static bool isDue({
    required int medicineCount,
    required DateTime? lastExport,
    required DateTime now,
    DateTime? snoozedUntil,
  }) {
    if (medicineCount == 0) return false;
    if (snoozedUntil != null && now.isBefore(snoozedUntil)) return false;
    return lastExport == null || now.difference(lastExport) > maxAge;
  }

  static Future<bool> isDueNow(int medicineCount,
      [SettingsService? settings]) async {
    final s = settings ?? SettingsService();
    return isDue(
      medicineCount: medicineCount,
      lastExport: await s.getLastBackupExport(),
      snoozedUntil: await s.getBackupReminderSnoozedUntil(),
      now: DateTime.now(),
    );
  }

  /// Da chiamare quando il file è stato salvato o condiviso davvero.
  static Future<void> markExported([SettingsService? settings]) async {
    await (settings ?? SettingsService()).setLastBackupExport(DateTime.now());
    changed.value++;
  }

  static Future<void> snoozeNow([SettingsService? settings]) async {
    await (settings ?? SettingsService())
        .setBackupReminderSnoozedUntil(DateTime.now().add(snooze));
    changed.value++;
  }
}

/// Testo da mostrare per un errore di backup o ripristino. I messaggi scritti
/// dall'app («Password errata o file corrotto») passano senza il prefisso
/// «Exception:»; gli errori tecnici del sistema diventano [fallback].
String backupErrorMessage(Object error, {required String fallback}) {
  const prefix = 'Exception: ';
  final text = error.toString();
  if (error is Exception && text.startsWith(prefix)) {
    return text.substring(prefix.length);
  }
  return fallback;
}
