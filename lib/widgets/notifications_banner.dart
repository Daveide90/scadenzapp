import 'package:flutter/material.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';

/// Avviso «Notifiche spente»: senza il permesso l'app non può ricordare
/// le scadenze, che è il suo scopo. Si ricontrolla a ogni ritorno nell'app,
/// perché il permesso si può cambiare dalle impostazioni di Android.
class NotificationsOffBanner extends StatefulWidget {
  final Future<bool> Function()? isEnabled;
  final Future<void> Function()? onEnable;

  const NotificationsOffBanner({super.key, this.isEnabled, this.onEnable});

  @override
  State<NotificationsOffBanner> createState() => _NotificationsOffBannerState();
}

class _NotificationsOffBannerState extends State<NotificationsOffBanner>
    with WidgetsBindingObserver {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    bool enabled;
    try {
      enabled = await (widget.isEnabled ?? NotificationService().areEnabled)();
    } catch (_) {
      enabled = true; // nel dubbio niente avviso
    }
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _enable() async {
    await (widget.onEnable ?? NotificationService().askToEnable)();
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    if (_enabled != false) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: AppColors.warning.withValues(alpha: 0.12),
      child: ListTile(
        leading: const Icon(Icons.notifications_off_outlined,
            color: AppColors.warning),
        title: const Text('Notifiche spente'),
        subtitle: const Text('ScadenzApp non può avvisarti delle scadenze.'),
        trailing: TextButton(onPressed: _enable, child: const Text('Attiva')),
      ),
    );
  }
}
