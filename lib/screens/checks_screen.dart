import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../database/database_helper.dart';
import '../models/cabinet.dart';
import '../models/cabinet_check.dart';
import '../providers/cabinet_provider.dart';
import '../services/check_report_pdf_service.dart';
import '../services/settings_service.dart';
import '../widgets/empty_state.dart';
import 'cabinet_check_screen.dart';
import '../theme/app_theme.dart';

/// Registro dei controlli agli armadietti, mese per mese, con il report
/// da consegnare o inviare.
class ChecksScreen extends StatefulWidget {
  const ChecksScreen({super.key});

  @override
  State<ChecksScreen> createState() => _ChecksScreenState();
}

class _ChecksScreenState extends State<ChecksScreen> {
  final _db = DatabaseHelper();
  final _settings = SettingsService();
  final _pdf = CheckReportPdfService();

  late DateTime _month;
  List<CabinetCheck> _checks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final from = _month;
    final to = DateTime(_month.year, _month.month + 1);
    final checks = await _db.getChecksBetween(from, to);
    if (!mounted) return;
    setState(() {
      _checks = checks;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  List<Cabinet> get _cabinets => context.read<CabinetProvider>().cabinets;

  String _cabinetName(int id) {
    for (final c in _cabinets) {
      if (c.id == id) return c.name;
    }
    return 'Armadietto eliminato';
  }

  Future<void> _newCheck() async {
    final cabinets = _cabinets;
    if (cabinets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea prima un armadietto')),
      );
      return;
    }

    final cabinet = cabinets.length == 1
        ? cabinets.first
        : await showDialog<Cabinet>(
            context: context,
            builder: (ctx) => SimpleDialog(
              title: const Text('Quale armadietto controlli?'),
              children: [
                for (final c in cabinets)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(ctx, c),
                    child: ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(c.name),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
              ],
            ),
          );
    if (cabinet == null || !mounted) return;

    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CabinetCheckScreen(cabinet: cabinet)),
    );
    if (saved == true) _load();
  }

  Future<void> _generateReport() async {
    final operator = await _askOperator();
    if (operator == null || !mounted) return;

    final rows = _checks
        .map((c) => CheckReportRow(
              check: c,
              cabinetName: _cabinetName(c.cabinetId),
            ))
        .toList();

    final checkedIds = _checks.map((c) => c.cabinetId).toSet();
    final missing = _cabinets
        .where((c) => !checkedIds.contains(c.id))
        .map((c) => c.name)
        .toList();

    final result = await _pdf.generate(
      month: _month,
      rows: rows,
      operator: operator,
      cabinetsWithoutChecks: missing,
    );
    if (result == null || !mounted) return;
    await _showDeliveryOptions(result);
  }

  /// Il report lo firma chi lo compila: proposto il nome salvato, modificabile.
  Future<String?> _askOperator() async {
    final controller =
        TextEditingController(text: await _settings.getOperatorName() ?? '');
    if (!mounted) {
      controller.dispose();
      return null;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chi firma il report?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Il nome comparirà in fondo al PDF, sopra lo spazio per la firma.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nome e cognome',
                border: OutlineInputBorder(),
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Genera PDF'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return null;
    await _settings.setOperatorName(name);
    return name;
  }

  Future<void> _showDeliveryOptions(CheckReportResult result) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child:
                  Text('Report creato', style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Periodo: ${result.periodLabel}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _saveToDevice(result);
            },
            child: const ListTile(
              leading: Icon(Icons.save_alt),
              title: Text('Salva sul dispositivo'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _sendByEmail(result);
            },
            child: const ListTile(
              leading: Icon(Icons.email_outlined),
              title: Text('Invia per email'),
              subtitle: Text('Alle email predefinite'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _pdf.share(result);
            },
            child: const ListTile(
              leading: Icon(Icons.share),
              title: Text('Condividi'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToDevice(CheckReportResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Salva report controlli',
        fileName: result.fileName,
        bytes: Uint8List.fromList(result.bytes),
      );
      if (path != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Report salvato'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(
            content: Text('Salvataggio non riuscito. Prova con «Condividi».')),
      );
    }
  }

  Future<void> _sendByEmail(CheckReportResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    final emails = await _settings.getRestockEmails();
    if (emails.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Nessuna email predefinita: impostale dalla schermata reintegro'),
        ),
      );
      await _pdf.share(result);
      return;
    }

    try {
      await FlutterEmailSender.send(Email(
        recipients: emails,
        subject: 'Report controlli armadietti ${result.periodLabel}',
        body: 'In allegato il report dei controlli di ${result.periodLabel}, '
            'generato da ScadenzApp.',
        attachmentPaths: [result.path],
      ));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Nessuna app email trovata: scegli dal menu Condividi'),
        ),
      );
      await _pdf.share(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Controlli'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Report del mese',
            onPressed: _generateReport,
          ),
        ],
      ),
      body: Column(
        children: [
          _MonthBar(
            month: _month,
            onPrev: () => _changeMonth(-1),
            onNext: _isCurrentMonth ? null : () => _changeMonth(1),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _checks.isEmpty
                    ? _emptyState()
                    : ListView.separated(
                        itemCount: _checks.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) => _CheckTile(
                          check: _checks[i],
                          cabinetName: _cabinetName(_checks[i].cabinetId),
                          onDelete: () => _deleteCheck(_checks[i]),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newCheck,
        icon: const Icon(Icons.add_task),
        label: const Text('Nuovo controllo'),
      ),
    );
  }

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _deleteCheck(CabinetCheck check) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare il controllo?'),
        content: Text(
          'Controllo del ${DateFormat('dd/MM/yyyy').format(check.performedAt)} '
          'di ${check.operator}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _db.deleteCabinetCheck(check.id!);
    _load();
  }

  Widget _emptyState() => EmptyState(
        image: 'nessun_controllo.png',
        title: 'Nessun controllo in ${CheckReportPdfService.monthLabel(_month)}',
        message: 'Registra il controllo di un armadietto: resta la traccia di '
            'chi ha verificato cosa, e a fine mese esce il report.',
      );
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.month, required this.onPrev, this.onNext});

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: Colors.grey.shade100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
            tooltip: 'Mese precedente',
          ),
          Text(
            CheckReportPdfService.monthLabel(month),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
            tooltip: 'Mese successivo',
          ),
        ],
      ),
    );
  }
}

class _CheckTile extends StatelessWidget {
  const _CheckTile({
    required this.check,
    required this.cabinetName,
    required this.onDelete,
  });

  final CabinetCheck check;
  final String cabinetName;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final color = check.isClear ? AppColors.primary : AppColors.expired;
    return ListTile(
      leading: Icon(
        check.isClear ? Icons.check_circle_outline : Icons.warning_amber_rounded,
        color: color,
      ),
      title: Text('$cabinetName · ${DateFormat('dd/MM/yyyy').format(check.performedAt)}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(check.operator, style: const TextStyle(fontSize: 13)),
          Text(
            '${check.checkedCount} verificate · ${check.expiredFound} scaduti · '
            '${check.removedCount} tolte',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          if (check.notes != null && check.notes!.isNotEmpty)
            Text(
              check.notes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade700),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Elimina questo controllo',
        color: Colors.grey.shade700,
        onPressed: onDelete,
      ),
    );
  }
}
