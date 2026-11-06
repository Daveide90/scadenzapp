import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_info.dart';
import '../legal/intended_use.dart';
import '../legal/licenses.dart';
import '../services/app_lock.dart';
import '../theme/app_theme.dart';
import '../widgets/notifications_banner.dart';

class SettingsScreen extends StatefulWidget {
  final DeviceUnlock? deviceUnlock;

  const SettingsScreen({super.key, this.deviceUnlock});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final DeviceUnlock _unlock = widget.deviceUnlock ?? LocalDeviceUnlock();

  /// Il telefono ha un PIN, una sequenza o un'impronta? null = lo sto chiedendo.
  bool? _available;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkAvailable();
  }

  Future<void> _checkAvailable() async {
    bool available;
    try {
      available = await _unlock.isAvailable();
    } catch (_) {
      available = false;
    }
    if (mounted) setState(() => _available = available);
  }

  /// Accendere e spegnere il blocco chiede lo sblocco del telefono. Se il
  /// telefono non ha più un blocco, spegnerlo non chiede niente: non c'è
  /// niente da proteggere.
  Future<void> _setLock(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final confirmed = _available == true
          ? await _unlock.authenticate(value
              ? 'Conferma per attivare il blocco'
              : 'Conferma per disattivare il blocco')
          : !value;
      if (confirmed) {
        await AppLock.setEnabled(value);
        messenger.showSnackBar(SnackBar(
            content: Text(value ? 'Blocco attivato' : 'Blocco disattivato')));
      }
    } catch (_) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Sblocco non riuscito: impostazione non cambiata')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        children: [
          const NotificationsOffBanner(),
          const _SectionTitle('Sicurezza'),
          ValueListenableBuilder<bool>(
            valueListenable: AppLock.enabled,
            builder: (context, enabled, _) {
              final available = _available;
              return SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Blocco con impronta o PIN'),
                subtitle: Text(available == false
                    ? 'Il telefono non ha un PIN, una sequenza o un\'impronta: '
                        'per usare il blocco impostali nelle impostazioni di Android.'
                    : 'All\'apertura e dopo 2 minuti fuori dall\'app chiede '
                        'l\'impronta, il volto o il PIN del telefono.'),
                value: enabled,
                onChanged: available == null ||
                        _busy ||
                        (available == false && !enabled)
                    ? null
                    : _setLock,
              );
            },
          ),
          const Divider(),
          const _SectionTitle('Informazioni'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Informazioni su ScadenzApp'),
            onTap: () => showInfoDialog(context),
          ),
          ListTile(
            leading: const Icon(Icons.rule_outlined),
            title: const Text('Uso previsto e avvertenze'),
            subtitle: const Text('Cosa fa l\'app e cosa non fa'),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const IntendedUseScreen())),
          ),
          ListTile(
            leading: const Icon(Icons.dataset_outlined),
            title: const Text('Dati dei farmaci'),
            subtitle: Text('AIFA, open data CC BY 4.0, al $aifaCatalogDateIt'),
            onTap: () => _showTextDialog(
                context, 'Dati dei farmaci', aifaAttribution),
          ),
          if (privacyPolicyUrl.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Informativa sulla privacy'),
              subtitle: const Text(privacyPolicyUrl),
              onTap: () => _showPrivacyDialog(context),
            ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Licenza d\'uso'),
            subtitle: const Text(
                'Gratis per il singolo professionista; non per le strutture'),
            onTap: () async {
              final testo = await rootBundle.loadString('LICENSE');
              if (!context.mounted) return;
              _showTextDialog(context, 'Licenza d\'uso', testo);
            },
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licenze'),
            subtitle: const Text('Componenti e dati usati dall\'app'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'ScadenzApp',
              applicationVersion: '$appVersion ($appBuild)',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
        ),
      );
}

void showInfoDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.medical_services, color: Colors.white, size: 28),
      ),
      title: const Text('ScadenzApp'),
      content: const SingleChildScrollView(
        child: Text(
          'Inventario delle scadenze dei farmaci negli armadietti.\n\n'
          'Lettura della confezione con la fotocamera, armadietti multipli, '
          'avvisi di scadenza, lista di reintegro, report dei controlli, '
          'backup cifrato. Tutto resta sul telefono.\n\n'
          'Versione $appVersion ($appBuild)',
          textAlign: TextAlign.center,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

void _showTextDialog(BuildContext context, String title, String text) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: SelectableText(text)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}

/// L'app non ha il permesso Internet e non apre il browser: l'indirizzo si
/// legge o si copia.
void _showPrivacyDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Informativa sulla privacy'),
      content: const SelectableText(
          'L\'informativa completa è pubblicata a questo indirizzo:\n\n'
          '$privacyPolicyUrl'),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(const ClipboardData(text: privacyPolicyUrl));
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('Copia l\'indirizzo'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Chiudi'),
        ),
      ],
    ),
  );
}
