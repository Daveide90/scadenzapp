import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import '../database/database_helper.dart';
import '../legal/intended_use.dart';
import '../models/cabinet.dart';
import '../providers/cabinet_provider.dart';
import '../services/backup_password.dart';
import '../services/backup_reminder.dart';
import '../services/backup_service.dart';
import '../utils/expiry_utils.dart';
import '../widgets/backup_reminder_banner.dart';
import '../widgets/empty_state.dart';
import '../widgets/notifications_banner.dart';
import 'cabinet_screen.dart';
import 'checks_screen.dart';
import 'custom_medicines_screen.dart';
import 'restock_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';
import '../theme/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    context
        .read<CabinetProvider>()
        .loadCabinets()
        .then((_) => _warnIfDataSetAside())
        .then((_) {
      if (mounted) showIntendedUseNoticeIfNeeded(context);
    });
  }

  /// Se il database di prima non si è potuto aprire è stato messo da parte
  /// (non cancellato): lo si dice una volta, con la via d'uscita.
  Future<void> _warnIfDataSetAside() async {
    final db = DatabaseHelper();
    if (db.setAsideFile == null || !mounted) return;
    db.setAsideFile = null;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: AppColors.expired, size: 36),
        title: const Text('I dati di prima non si sono aperti'),
        content: const Text(
          'Il database salvato non si è potuto leggere, per esempio dopo un '
          'cambio di telefono o per un file rovinato. Non è stato cancellato: '
          'è stato messo da parte, e l\'app riparte vuota.\n\n'
          'Se hai un backup, ripristinalo adesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Più tardi'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showRestoreDialog();
            },
            child: const Text('Ripristina un backup'),
          ),
        ],
      ),
    );
  }

  // ─── Dialoghi armadietti ──────────────────────────────────

  void _showAddDialog() {
    final controller = TextEditingController();
    var submitted = false; // anti doppio invio (Invio da tastiera + tap "Crea")
    void submit(BuildContext ctx) {
      if (submitted) return;
      final name = controller.text.trim();
      if (name.isEmpty) return;
      submitted = true;
      context.read<CabinetProvider>().createCabinet(name);
      Navigator.pop(ctx);
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuovo armadietto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Nome',
            hintText: 'es. Pronto Soccorso',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => submit(ctx),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => submit(ctx),
            child: const Text('Crea'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _showRenameDialog(Cabinet cabinet) {
    final controller = TextEditingController(text: cabinet.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rinomina armadietto'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: 'Nome',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                context.read<CabinetProvider>().renameCabinet(cabinet.id!, name);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _confirmDelete(Cabinet cabinet) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina armadietto'),
        content: Text(
          cabinet.medicineCount > 0
              ? 'Eliminare "${cabinet.name}" con ${cabinet.medicineCount} farmac${cabinet.medicineCount == 1 ? 'o' : 'i'}?\n\nQuesta azione non è reversibile.'
              : 'Eliminare "${cabinet.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () {
              context.read<CabinetProvider>().deleteCabinet(cabinet.id!);
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
  }

  // ─── Backup ───────────────────────────────────────────────

  /// Mostra dialog backup con password. [cabinetId] null = backup completo.
  void _showBackupPasswordDialog({int? cabinetId, String? cabinetName}) {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final title = cabinetId != null
        ? 'Backup "$cabinetName"'
        : 'Backup completo';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              cabinetId != null
                  ? 'Il backup includerà tutti i farmaci di "$cabinetName".'
                  : 'Il backup includerà tutti gli armadietti e farmaci.',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Password di cifratura *',
                hintText: 'Minimo 12 caratteri',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            // Doppia immissione: una password scritta male = backup illeggibile.
            TextField(
              controller: confirmController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Ripeti la password *',
                hintText: 'Deve coincidere',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_person_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annulla'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.backup, size: 18),
            label: const Text('Crea backup'),
            onPressed: () {
              final pwd = passwordController.text;
              final problema = backupPasswordProblem(pwd, confirmController.text);
              if (problema != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(problema), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(ctx);
              _createBackup(pwd, cabinetId);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createBackup(String password, int? cabinetId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      messenger.showSnackBar(
        const SnackBar(content: Text('Creazione backup in corso...')),
      );

      final backup = BackupService();
      final path = await backup.createBackup(
        password: password,
        cabinetId: cabinetId,
      );

      if (mounted) {
        messenger.clearSnackBars();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: AppColors.primary, size: 48),
            title: const Text('Backup creato'),
            content: const Text(
              'Il file è cifrato con la tua password, ma per ora sta solo '
              'dentro l\'app: se l\'app viene disinstallata o il telefono si '
              'rompe, sparisce con lei.\n\n'
              'Salvalo nella memoria del telefono (per esempio in Download) '
              'o mandalo dove potrai ritrovarlo.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Chiudi'),
              ),
              TextButton.icon(
                icon: const Icon(Icons.share),
                label: const Text('Condividi'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _shareBackup(path);
                },
              ),
              FilledButton.icon(
                icon: const Icon(Icons.save_alt),
                label: const Text('Salva sul dispositivo'),
                onPressed: () {
                  Navigator.pop(ctx);
                  _saveBackupToDevice(path);
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(backupErrorMessage(e,
                fallback: 'Backup non riuscito. Controlla che ci sia spazio '
                    'libero sul telefono e riprova.')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Copia il backup dove sceglie l'utente (selettore di Android): fuori
  /// dalla cartella dell'app sopravvive alla disinstallazione.
  Future<void> _saveBackupToDevice(String path) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Salva il backup',
        fileName: path.split('/').last,
        bytes: await File(path).readAsBytes(),
      );
      if (saved == null) return; // annullato
      await BackupReminder.markExported();
      messenger.showSnackBar(const SnackBar(
        content: Text('Backup salvato'),
        backgroundColor: AppColors.primary,
      ));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Salvataggio non riuscito. Prova con «Condividi».'),
        backgroundColor: Colors.red,
      ));
    }
  }

  Future<void> _shareBackup(String path) async {
    try {
      final result = await Share.shareXFiles([XFile(path)],
          subject: 'ScadenzApp Backup');
      // «unavailable»: Android non dice se è andato a buon fine; si conta,
      // altrimenti il promemoria insisterebbe dopo ogni condivisione.
      if (result.status != ShareResultStatus.dismissed) {
        await BackupReminder.markExported();
      }
    } catch (_) {
      // condivisione annullata o non disponibile: il promemoria resta
    }
  }

  void _showRestoreDialog() async {
    final dir = await getApplicationDocumentsDirectory();
    final allFiles = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.bak'))
        .toList();
    allFiles.sort((a, b) => b.path.compareTo(a.path));

    if (!mounted) return;

    final passwordController = TextEditingController();
    File? selectedFile = allFiles.isNotEmpty ? allFiles.first : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(Icons.restore, color: Colors.orange, size: 40),
          title: const Text('Ripristina backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allFiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Nessun backup nella cartella dell\'app.\nImporta un file .bak (Download, Telegram, ecc.).',
                    style: TextStyle(fontSize: 13),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<File>(
                        key: ValueKey(selectedFile?.path),
                        initialValue: selectedFile,
                        decoration: const InputDecoration(
                          labelText: 'File di backup',
                          border: OutlineInputBorder(),
                        ),
                        isExpanded: true,
                        items: allFiles.map((f) {
                          final name = f.path.split('/').last;
                          return DropdownMenuItem(value: f, child: Text(name, style: const TextStyle(fontSize: 13)));
                        }).toList(),
                        onChanged: (v) => setDialogState(() => selectedFile = v),
                      ),
                    ),
                    // Si eliminano solo i backup nella cartella dell'app, mai
                    // un file importato da fuori.
                    if (selectedFile != null &&
                        selectedFile!.parent.path == dir.path)
                      IconButton(
                        tooltip: 'Elimina questo backup',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final file = selectedFile!;
                          final ok = await _confirmDeleteBackup(
                              ctx, file.path.split('/').last);
                          if (!ok) return;
                          try {
                            await file.delete();
                          } catch (_) {
                            // già sparito: lo si toglie comunque dall'elenco
                          }
                          setDialogState(() {
                            allFiles.remove(file);
                            selectedFile =
                                allFiles.isNotEmpty ? allFiles.first : null;
                          });
                        },
                      ),
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('Importa da file…'),
                  onPressed: () async {
                    final result = await FilePicker.pickFiles();
                    final path = result?.files.single.path;
                    if (path == null) return;
                    final picked = File(path);
                    setDialogState(() {
                      if (!allFiles.any((x) => x.path == picked.path)) {
                        allFiles.insert(0, picked);
                      }
                      selectedFile = picked;
                    });
                  },
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, size: 18, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Prima di applicare qualsiasi modifica ti verrà mostrato '
                        'cosa contiene il backup (completo o singolo armadietto).',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annulla'),
            ),
            FilledButton(
              onPressed: () async {
                final pwd = passwordController.text;
                if (pwd.isEmpty || selectedFile == null) return;
                Navigator.pop(ctx);
                _doRestore(selectedFile!.path, pwd);
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Ripristina'),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteBackup(BuildContext ctx, String name) async =>
      await showDialog<bool>(
        context: ctx,
        builder: (c) => AlertDialog(
          title: const Text('Eliminare il backup?'),
          content: Text('$name\n\nViene tolto dalla cartella dell\'app. '
              'Le copie salvate altrove non vengono toccate.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Annulla'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Elimina'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _doRestore(String path, String password) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);

    // FASE 1: decifra e legge il backup SENZA applicarlo.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingOverlay(message: 'Lettura backup in corso…'),
    );

    BackupInfo? info;
    Object? readError;
    try {
      info = await BackupService().readBackup(filePath: path, password: password);
    } catch (e) {
      readError = e;
    } finally {
      if (navigator.canPop()) navigator.pop();
    }

    if (!mounted) return;
    if (readError != null || info == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(backupErrorMessage(readError ?? 'vuoto',
              fallback: 'Impossibile leggere il backup: il file potrebbe '
                  'essere incompleto o danneggiato.')),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // FASE 2: conferma esplicita, diversa per tipo di backup.
    final df = DateFormat('dd/MM/yyyy HH:mm');
    final when = info.createdAt != null ? df.format(info.createdAt!) : 'data sconosciuta';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          info!.isFull ? Icons.warning_amber : Icons.inventory_2_outlined,
          color: info.isFull ? Colors.red : Colors.orange,
          size: 40,
        ),
        title: Text(info.isFull
            ? 'Ripristino COMPLETO'
            : 'Ripristino armadietto "${info.cabinetName ?? '?'}"'),
        content: Text(
          info.isFull
              ? 'Backup completo del $when: contiene ${info.cabinetCount} '
                  'armadietti e ${info.medicineCount} farmaci.\n\n'
                  '⚠️ SOSTITUISCE TUTTI I DATI ATTUALI: gli armadietti e i '
                  'farmaci presenti ora verranno eliminati.'
              : 'Backup dell\'armadietto "${info.cabinetName ?? '?'}" del '
                  '$when (${info.medicineCount} farmaci).\n\n'
                  'Se questo armadietto esiste già nell\'app verrà '
                  'SOSTITUITO (la versione attuale viene eliminata); '
                  'altrimenti verrà AGGIUNTO senza toccare gli altri.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: info.isFull ? Colors.red : Colors.orange,
            ),
            child: Text(info.isFull ? 'Sostituisci tutto' : 'Ripristina armadietto'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // FASE 3: applica.
    final provider = context.read<CabinetProvider>();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _LoadingOverlay(message: 'Ripristino in corso…'),
    );

    String? result;
    Object? error;
    try {
      result = await BackupService().applyBackup(info);
      await provider.loadCabinets();
    } catch (e) {
      error = e;
    } finally {
      // Chiudi SEMPRE il badge dal navigator catturato (NON legato a `mounted`:
      // se lo State si smonta durante il restore, il badge non chiudibile resterebbe
      // appeso per sempre).
      if (navigator.canPop()) navigator.pop();
    }

    if (!mounted) return;
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(backupErrorMessage(error,
              fallback: 'Ripristino non riuscito: i dati di prima sono '
                  'rimasti com\'erano. Riprova.')),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Backup $result ripristinato'),
          backgroundColor: AppColors.primary,
        ),
      );
    }
  }

  // ─── Build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ScadenzApp'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Cerca per nome o lotto',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Controlli e report',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChecksScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.medication_liquid_outlined),
            tooltip: 'Farmaci personalizzati',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomMedicinesScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Impostazioni',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Senza permesso l'app non può ricordare le scadenze: lo si dice.
          const NotificationsOffBanner(),
          // I dati stanno solo sul telefono: si ricorda il backup salvato fuori.
          Selector<CabinetProvider, int>(
            selector: (_, p) =>
                p.cabinets.fold(0, (sum, c) => sum + c.medicineCount),
            builder: (_, count, __) => BackupReminderBanner(
              medicineCount: count,
              onBackup: () => _showBackupPasswordDialog(),
            ),
          ),
          Expanded(
            child: Consumer<CabinetProvider>(
              builder: (context, provider, _) {
                if (provider.loadError && provider.cabinets.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          const Text('Impossibile aprire i dati',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 8),
                          Text(
                            'Errore nel caricamento del database. Riprova; se persiste, riavvia l\'app.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () =>
                                context.read<CabinetProvider>().loadCabinets(),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Riprova'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                if (provider.cabinets.isEmpty) {
                  return Column(
                    children: [
                      _BackupSection(
                        onBackupAll: () => _showBackupPasswordDialog(),
                        onRestore: _showRestoreDialog,
                      ),
                      const Expanded(
                        child: EmptyState(
                          image: 'armadietti.png',
                          title: 'Nessun armadietto',
                          message: 'Crea il tuo primo armadietto: è il posto dove '
                              'tieni i farmaci e ne segui le scadenze.',
                        ),
                      ),
                    ],
                  );
                }

                return ListView(
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    // Sezione Backup in alto
                    _BackupSection(
                      onBackupAll: () => _showBackupPasswordDialog(),
                      onRestore: _showRestoreDialog,
                    ),
                    // Lista armadietti
                    ...provider.cabinets.map((cabinet) => Column(
                      children: [
                        _CabinetListItem(
                          cabinet: cabinet,
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CabinetScreen(cabinet: cabinet),
                              ),
                            );
                            if (mounted) provider.loadCabinetsIfNeeded();
                          },
                          onRename: () => _showRenameDialog(cabinet),
                          onDelete: () => _confirmDelete(cabinet),
                          onBackup: () => _showBackupPasswordDialog(
                            cabinetId: cabinet.id!,
                            cabinetName: cabinet.name,
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                    )),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        child: const Icon(Icons.add),
      ),
      // Accesso ben visibile alla lista "Da reintegrare" (richiesta betatest:
      // l'icona in AppBar non si capiva).
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.assignment_late),
              label: const Text(
                'Scadenze e reintegro',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              onPressed: () async {
                final provider = context.read<CabinetProvider>();
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RestockScreen()),
                );
                if (mounted) {
                  provider.loadCabinetsIfNeeded();
                }
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sezione Backup ─────────────────────────────────────────

class _BackupSection extends StatelessWidget {
  final VoidCallback onBackupAll;
  final VoidCallback onRestore;

  const _BackupSection({
    required this.onBackupAll,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: Colors.white70, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Backup & Ripristino',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _BackupButton(
                icon: Icons.backup,
                label: 'Backup',
                onTap: onBackupAll,
                filled: true,
              ),
              const SizedBox(width: 8),
              _BackupButton(
                icon: Icons.restore,
                label: 'Ripristina',
                onTap: onRestore,
                filled: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackupButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _BackupButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? Colors.white : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: filled ? null : Border.all(color: Colors.white54),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 15,
                color: filled ? AppColors.primary : Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: filled ? AppColors.primary : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Cabinet List Item ──────────────────────────────────────

class _CabinetListItem extends StatelessWidget {
  final Cabinet cabinet;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onBackup;

  const _CabinetListItem({
    required this.cabinet,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
    required this.onBackup,
  });

  @override
  Widget build(BuildContext context) {
    final hasExpiry = cabinet.nearestExpiry != null;
    final expiryColor = hasExpiry ? getExpiryColor(cabinet.nearestExpiry!) : null;
    final df = DateFormat('dd/MM/yyyy');

    return InkWell(
      onTap: onTap,
      onLongPress: () => _showCabinetMenu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Icona armadietto
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.medical_services_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    cabinet.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${cabinet.medicineCount} farmac${cabinet.medicineCount == 1 ? 'o' : 'i'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  if (hasExpiry) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: expiryColor!.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Scad: ${df.format(cabinet.nearestExpiry!)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: getExpiryTextColor(cabinet.nearestExpiry!),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Backup singolo armadietto
            IconButton(
              icon: Icon(Icons.backup_outlined, size: 20, color: Colors.grey.shade500),
              tooltip: 'Backup ${cabinet.name}',
              onPressed: onBackup,
            ),
            // Arrow
            Icon(Icons.chevron_right, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  void _showCabinetMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rinomina'),
              onTap: () {
                Navigator.pop(ctx);
                onRename();
              },
            ),
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Backup'),
              onTap: () {
                Navigator.pop(ctx);
                onBackup();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Elimina', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Badge "caricamento in corso" (persistente, non chiudibile) ─────────────

class _LoadingOverlay extends StatelessWidget {
  final String message;

  const _LoadingOverlay({required this.message});

  @override
  Widget build(BuildContext context) {
    // canPop:false → non si chiude col tasto indietro finché il caricamento è in corso.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 18),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
