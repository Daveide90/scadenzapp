import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Impostazioni semplici (non sensibili) persistite nel secure storage,
/// riusando lo stesso backend già adottato dall'app (nessuna nuova dipendenza).
/// NB: non attivare encryptedSharedPreferences (vedi nota in database_helper).
class SettingsService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  static const _kRedMonths = 'restock_red_months';
  static const _kYellowMonths = 'restock_yellow_months';
  static const _kScanCamera = 'scan_camera_name';
  static const _kRestockEmails = 'restock_emails';
  static const _kOperatorName = 'operator_name';
  static const _kAppLock = 'app_lock_enabled';
  static const _kLastBackupExport = 'last_backup_export';
  static const _kBackupSnooze = 'backup_reminder_snoozed_until';
  static const _kIntendedUseAck = 'intended_use_ack_v1';

  static const int defaultRedMonths = 1; // ammessi: 1 o 2
  static const int defaultYellowMonths = 3; // ammessi: 3..6

  Future<int> getRedMonths() async {
    final n = int.tryParse(await _storage.read(key: _kRedMonths) ?? '');
    return (n == 1 || n == 2) ? n! : defaultRedMonths;
  }

  Future<void> setRedMonths(int months) async {
    final v = (months == 1 || months == 2) ? months : defaultRedMonths;
    await _storage.write(key: _kRedMonths, value: v.toString());
  }

  Future<int> getYellowMonths() async {
    final n = int.tryParse(await _storage.read(key: _kYellowMonths) ?? '');
    return (n != null && n >= 3 && n <= 6) ? n : defaultYellowMonths;
  }

  Future<void> setYellowMonths(int months) async {
    final v = (months >= 3 && months <= 6) ? months : defaultYellowMonths;
    await _storage.write(key: _kYellowMonths, value: v.toString());
  }

  /// Nome (id piattaforma) della fotocamera scelta per la scansione,
  /// null = default. Se la fotocamera non esiste più si torna al default.
  Future<String?> getScanCameraName() => _storage.read(key: _kScanCamera);

  Future<void> setScanCameraName(String name) =>
      _storage.write(key: _kScanCamera, value: name);

  /// Email predefinite a cui inviare il PDF del reintegro (una per riga).
  Future<List<String>> getRestockEmails() async {
    final raw = await _storage.read(key: _kRestockEmails) ?? '';
    return raw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> setRestockEmails(List<String> emails) =>
      _storage.write(key: _kRestockEmails, value: emails.join('\n'));

  /// Nome di chi esegue i controlli: viene proposto come predefinito e
  /// finisce nel report mensile.
  Future<String?> getOperatorName() async {
    final v = (await _storage.read(key: _kOperatorName))?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> setOperatorName(String name) =>
      _storage.write(key: _kOperatorName, value: name.trim());

  /// Blocco dell'app con lo sblocco del telefono. Di serie è attivo: si
  /// spegne solo se l'utente l'ha scelto.
  Future<bool> getAppLockEnabled() async =>
      (await _storage.read(key: _kAppLock)) != 'false';

  Future<void> setAppLockEnabled(bool enabled) =>
      _storage.write(key: _kAppLock, value: enabled.toString());

  /// Ultima volta che un backup è stato salvato o condiviso fuori dall'app.
  Future<DateTime?> getLastBackupExport() async =>
      DateTime.tryParse(await _storage.read(key: _kLastBackupExport) ?? '');

  Future<void> setLastBackupExport(DateTime when) =>
      _storage.write(key: _kLastBackupExport, value: when.toIso8601String());

  /// Fino a quando il promemoria del backup resta zitto («Più tardi»).
  Future<DateTime?> getBackupReminderSnoozedUntil() async =>
      DateTime.tryParse(await _storage.read(key: _kBackupSnooze) ?? '');

  Future<void> setBackupReminderSnoozedUntil(DateTime until) =>
      _storage.write(key: _kBackupSnooze, value: until.toIso8601String());

  /// L'utente ha letto «Prima di iniziare» (uso previsto e avvertenze).
  Future<bool> getIntendedUseAcknowledged() async =>
      (await _storage.read(key: _kIntendedUseAck)) == 'true';

  Future<void> setIntendedUseAcknowledged() =>
      _storage.write(key: _kIntendedUseAck, value: 'true');
}
