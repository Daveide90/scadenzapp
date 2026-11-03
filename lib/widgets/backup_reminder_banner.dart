import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/backup_reminder.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';

/// Avviso nella home quando manca un backup salvato fuori dall'app, o
/// quando l'ultimo ha più di 30 giorni. I dati stanno solo sul telefono:
/// senza un backup fuori, un telefono rotto o una disinstallazione li
/// cancellano.
class BackupReminderBanner extends StatefulWidget {
  final int medicineCount;
  final VoidCallback onBackup;

  /// Iniettabili per i test; di serie leggono le impostazioni.
  final Future<bool> Function(int medicineCount)? isDue;
  final Future<DateTime?> Function()? lastExport;
  final Future<void> Function()? onSnooze;

  const BackupReminderBanner({
    super.key,
    required this.medicineCount,
    required this.onBackup,
    this.isDue,
    this.lastExport,
    this.onSnooze,
  });

  @override
  State<BackupReminderBanner> createState() => _BackupReminderBannerState();
}

class _BackupReminderBannerState extends State<BackupReminderBanner> {
  bool _due = false;
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    BackupReminder.changed.addListener(_check);
    _check();
  }

  @override
  void didUpdateWidget(BackupReminderBanner old) {
    super.didUpdateWidget(old);
    if (old.medicineCount != widget.medicineCount) _check();
  }

  @override
  void dispose() {
    BackupReminder.changed.removeListener(_check);
    super.dispose();
  }

  Future<void> _check() async {
    bool due;
    DateTime? last;
    try {
      due = await (widget.isDue ?? BackupReminder.isDueNow)(
          widget.medicineCount);
      last = await (widget.lastExport ?? SettingsService().getLastBackupExport)();
    } catch (_) {
      due = false; // nel dubbio niente avviso
    }
    if (mounted) {
      setState(() {
        _due = due;
        _last = last;
      });
    }
  }

  Future<void> _snooze() async {
    await (widget.onSnooze ?? BackupReminder.snoozeNow)();
    if (mounted) setState(() => _due = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_due) return const SizedBox.shrink();
    final last = _last;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: AppColors.warning.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.backup_outlined, color: AppColors.warning),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    last == null
                        ? 'Nessun backup salvato fuori dall\'app. Se il '
                            'telefono si rompe o l\'app viene disinstallata, '
                            'i dati si perdono.'
                        : 'L\'ultimo backup salvato fuori dall\'app è del '
                            '${DateFormat('dd/MM/yyyy').format(last)}.',
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                children: [
                  TextButton(
                    onPressed: _snooze,
                    child: const Text('Più tardi'),
                  ),
                  TextButton(
                    onPressed: widget.onBackup,
                    child: const Text('Fai il backup'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
