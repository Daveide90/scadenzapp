import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../models/medicine.dart';
import '../services/restock_pdf_service.dart';
import '../services/settings_service.dart';
import '../utils/expiry_utils.dart';
import '../widgets/empty_state.dart';
import '../theme/app_theme.dart';

class _RestockItem {
  final Medicine medicine;
  final String cabinetName;

  _RestockItem({required this.medicine, required this.cabinetName});

  RestockPdfRow toPdfRow() => RestockPdfRow(
        name: medicine.name,
        quantity: medicine.quantity,
        expirationDate: medicine.expirationDate,
        cabinetName: cabinetName,
      );
}

/// Cosa includere nel PDF.
enum _PdfScope { red, yellow, all }

class RestockScreen extends StatefulWidget {
  const RestockScreen({super.key});

  @override
  State<RestockScreen> createState() => _RestockScreenState();
}

class _RestockScreenState extends State<RestockScreen> {
  final _settings = SettingsService();

  int _redMonths = SettingsService.defaultRedMonths;
  int _yellowMonths = SettingsService.defaultYellowMonths;

  List<_RestockItem> _expired = [];
  List<_RestockItem> _red = [];
  List<_RestockItem> _yellow = [];
  bool _loading = true;

  /// Filtro armadietti della schermata: null = tutti.
  Set<String>? _cabinetFilter;

  static const _darkRed = AppColors.expired; // red900
  static const _lightRed = AppColors.expiring; // red400
  Color get _amber => Colors.amber.shade700;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final redMonths = await _settings.getRedMonths();
    final yellowMonths = await _settings.getYellowMonths();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yellowLimit = addMonths(today, yellowMonths);

    final rows = await DatabaseHelper().getExpiringMedicines(yellowLimit);

    final expired = <_RestockItem>[];
    final red = <_RestockItem>[];
    final yellow = <_RestockItem>[];

    for (final row in rows) {
      final med = Medicine.fromMap(row);
      final item = _RestockItem(
        medicine: med,
        cabinetName: row['cabinet_name'] as String,
      );
      switch (classifyRestock(
        med.expirationDate,
        redMonths: redMonths,
        yellowMonths: yellowMonths,
        now: now,
      )) {
        case RestockBand.expired:
          expired.add(item);
        case RestockBand.red:
          red.add(item);
        case RestockBand.yellow:
          yellow.add(item);
        case RestockBand.none:
          break; // oltre la soglia gialla: non mostrato
      }
    }

    if (!mounted) return;
    setState(() {
      _redMonths = redMonths;
      _yellowMonths = yellowMonths;
      _expired = expired;
      _red = red;
      _yellow = yellow;
      _loading = false;
    });
  }

  String _monthsLabel(int months) => months == 1 ? '1 mese' : '$months mesi';

  Future<void> _setRedMonths(int months) async {
    await _settings.setRedMonths(months);
    ExpiryThresholds.redMonths = months; // vale anche per home e armadietti
    setState(() => _loading = true);
    await _load();
  }

  Future<void> _setYellowMonths(int months) async {
    await _settings.setYellowMonths(months);
    ExpiryThresholds.yellowMonths = months; // vale anche per home e armadietti
    setState(() => _loading = true);
    await _load();
  }

  // --- Filtro armadietti ---

  /// Armadietti presenti nelle liste correnti.
  List<String> get _allCabinetNames => <String>{
        for (final i in [..._expired, ..._red, ..._yellow]) i.cabinetName,
      }.toList()
        ..sort();

  /// Applica il filtro armadietti della schermata a una lista.
  List<_RestockItem> _visible(List<_RestockItem> items) {
    final filter = _cabinetFilter;
    if (filter == null) return items;
    return items.where((i) => filter.contains(i.cabinetName)).toList();
  }

  void _toggleCabinet(String name) {
    setState(() {
      final all = _allCabinetNames.toSet();
      final sel = Set<String>.of(_cabinetFilter ?? all);
      if (sel.contains(name)) {
        sel.remove(name);
      } else {
        sel.add(name);
      }
      _cabinetFilter = sel.length == all.length ? null : sel;
    });
  }

  // --- Export PDF ---

  Future<void> _showPdfOptions() async {
    var scope = _PdfScope.all;
    var includeExpired = true;
    final allCabinets = _allCabinetNames;
    // Parte dalla selezione già attiva nella schermata.
    final selectedCabinets =
        Set<String>.of(_cabinetFilter ?? allCabinets.toSet());

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheet) {
            // Conteggi coerenti con gli armadietti selezionati.
            int countIn(List<_RestockItem> items) => items
                .where((i) => selectedCabinets.contains(i.cabinetName))
                .length;
            final redCount = countIn(_red);
            final yellowCount = countIn(_yellow);
            final expiredCount = countIn(_expired);

            Widget scopeTile(_PdfScope value, String label, String subtitle) {
              return RadioListTile<_PdfScope>(
                value: value,
                title: Text(label),
                subtitle: Text(subtitle),
                dense: true,
                activeColor: AppColors.primary,
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Esporta PDF',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      RadioGroup<_PdfScope>(
                        groupValue: scope,
                        onChanged: (v) => setSheet(() => scope = v!),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            scopeTile(_PdfScope.red, 'Solo rossi',
                                'In scadenza entro ${_monthsLabel(_redMonths)} ($redCount)'),
                            scopeTile(_PdfScope.yellow, 'Solo gialli',
                                'Attenzione entro ${_monthsLabel(_yellowMonths)} ($yellowCount)'),
                            scopeTile(_PdfScope.all, 'Tutti',
                                'Rossi + gialli (${redCount + yellowCount})'),
                          ],
                        ),
                      ),
                      const Divider(),
                      CheckboxListTile(
                        value: includeExpired,
                        onChanged: (v) =>
                            setSheet(() => includeExpired = v ?? false),
                        title: const Text('Includi anche gli scaduti'),
                        subtitle: Text('$expiredCount scaduti'),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        activeColor: _darkRed,
                      ),
                      if (allCabinets.length > 1) ...[
                        const Divider(),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Armadietti da includere',
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            TextButton(
                              onPressed: () => setSheet(() {
                                if (selectedCabinets.length ==
                                    allCabinets.length) {
                                  selectedCabinets.clear();
                                } else {
                                  selectedCabinets.addAll(allCabinets);
                                }
                              }),
                              child: Text(
                                selectedCabinets.length == allCabinets.length
                                    ? 'Nessuno'
                                    : 'Tutti',
                              ),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 0,
                          children: allCabinets.map((name) {
                            return FilterChip(
                              label: Text(name,
                                  style: const TextStyle(fontSize: 13)),
                              selected: selectedCabinets.contains(name),
                              selectedColor: AppColors.primary
                                  .withValues(alpha: 0.2),
                              checkmarkColor: AppColors.primary,
                              onSelected: (sel) => setSheet(() {
                                if (sel) {
                                  selectedCabinets.add(name);
                                } else {
                                  selectedCabinets.remove(name);
                                }
                              }),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          onPressed: selectedCabinets.isEmpty
                              ? null
                              : () {
                                  Navigator.pop(sheetCtx);
                                  _generatePdf(scope, includeExpired,
                                      selectedCabinets);
                                },
                          icon: const Icon(Icons.picture_as_pdf),
                          label: const Text('Genera PDF'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _generatePdf(
      _PdfScope scope, bool includeExpired, Set<String> cabinets) async {
    List<RestockPdfRow> filtered(List<_RestockItem> items) => items
        .where((i) => cabinets.contains(i.cabinetName))
        .map((i) => i.toPdfRow())
        .toList();

    final expired = includeExpired ? filtered(_expired) : <RestockPdfRow>[];
    final red = (scope == _PdfScope.red || scope == _PdfScope.all)
        ? filtered(_red)
        : <RestockPdfRow>[];
    final yellow = (scope == _PdfScope.yellow || scope == _PdfScope.all)
        ? filtered(_yellow)
        : <RestockPdfRow>[];

    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await RestockPdfService().generate(
        expired: expired,
        red: red,
        yellow: yellow,
        redMonths: _redMonths,
        yellowMonths: _yellowMonths,
      );
      if (result == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nessun farmaco da includere nel PDF')),
        );
        return;
      }
      if (!mounted) return;
      await _showDeliveryOptions(result);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('PDF non generato. Riprova.')),
      );
    }
  }

  /// PDF pronto: salva sul dispositivo, invia per email o condividi.
  Future<void> _showDeliveryOptions(RestockPdfResult result) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('PDF creato',
                  style: Theme.of(ctx).textTheme.titleLarge),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              'Armadietti: ${result.cabinetNames.join(', ')}',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _savePdfToDevice(result);
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
              _sendPdfByEmail(result);
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
              RestockPdfService().share(result);
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

  Future<void> _savePdfToDevice(RestockPdfResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Salva PDF reintegro',
        fileName: result.fileName,
        bytes: Uint8List.fromList(result.bytes),
      );
      if (path != null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('PDF salvato'),
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

  Future<void> _sendPdfByEmail(RestockPdfResult result) async {
    final messenger = ScaffoldMessenger.of(context);
    var emails = await _settings.getRestockEmails();
    if (emails.isEmpty) {
      if (!mounted) return;
      await _showEmailSettings();
      emails = await _settings.getRestockEmails();
      if (emails.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
              content: Text('Nessuna email predefinita impostata')),
        );
        return;
      }
    }

    final email = Email(
      recipients: emails,
      subject:
          'Reintegro farmaci ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
      body: 'Ecco il reintegro da eseguire per gli armadietti di: '
          '${result.cabinetNames.join(', ')}.\n\n'
          'In allegato il PDF generato da ScadenzApp.',
      attachmentPaths: [result.path],
    );

    try {
      await FlutterEmailSender.send(email);
    } catch (_) {
      // Nessuna app email configurata: fallback sul menu Condividi.
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('Nessuna app email trovata: scegli dal menu Condividi'),
        ),
      );
      await RestockPdfService().share(result);
    }
  }

  /// Gestione delle email predefinite (una per riga).
  Future<void> _showEmailSettings() async {
    final current = await _settings.getRestockEmails();
    if (!mounted) return;
    final controller = TextEditingController(text: current.join('\n'));

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Email predefinite'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Il PDF del reintegro verrà inviato a questi indirizzi. '
              'Una email per riga.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                hintText: 'farmacia@ospedale.it\ncaposala@reparto.it',
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
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary),
            onPressed: () async {
              final emails = controller.text
                  .split(RegExp(r'[\n,;]'))
                  .map((e) => e.trim())
                  .where((e) => e.contains('@') && e.contains('.'))
                  .toList();
              await _settings.setRestockEmails(emails);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Salva'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expired = _visible(_expired);
    final red = _visible(_red);
    final yellow = _visible(_yellow);
    final total = expired.length + red.length + yellow.length;
    final allCabinets = _allCabinetNames;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Da reintegrare'),
        actions: [
          IconButton(
            icon: const Icon(Icons.alternate_email),
            tooltip: 'Email predefinite per il PDF',
            onPressed: _showEmailSettings,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _ThresholdBar(
                  redMonths: _redMonths,
                  yellowMonths: _yellowMonths,
                  onRedChanged: _setRedMonths,
                  onYellowChanged: _setYellowMonths,
                ),
                // Filtro per armadietto: la lista E il PDF seguono la scelta.
                if (allCabinets.length > 1)
                  Material(
                    color: Colors.grey.shade100,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
                      child: Row(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 18, color: Colors.grey.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final name in allCabinets)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(right: 6),
                                      child: FilterChip(
                                        label: Text(name,
                                            style: const TextStyle(
                                                fontSize: 12)),
                                        visualDensity:
                                            VisualDensity.compact,
                                        selected: _cabinetFilter == null ||
                                            _cabinetFilter!.contains(name),
                                        selectedColor: AppColors.primary
                                            .withValues(alpha: 0.18),
                                        checkmarkColor:
                                            AppColors.primary,
                                        onSelected: (_) =>
                                            _toggleCabinet(name),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          if (_cabinetFilter != null)
                            TextButton(
                              onPressed: () =>
                                  setState(() => _cabinetFilter = null),
                              child: const Text('Tutti',
                                  style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: total == 0
                      ? _emptyState()
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 88),
                          children: [
                            if (expired.isNotEmpty)
                              _Section(
                                title: 'Scaduti',
                                color: _darkRed,
                                icon: Icons.error,
                                textColor: restockTextColor(RestockBand.expired),
                                items: expired,
                              ),
                            if (red.isNotEmpty)
                              _Section(
                                title:
                                    'In scadenza (entro ${_monthsLabel(_redMonths)})',
                                color: _lightRed,
                                icon: Icons.warning_amber,
                                textColor: restockTextColor(RestockBand.red),
                                items: red,
                              ),
                            if (yellow.isNotEmpty)
                              _Section(
                                title:
                                    'Attenzione (entro ${_monthsLabel(_yellowMonths)})',
                                color: _amber,
                                icon: Icons.schedule,
                                textColor: restockTextColor(RestockBand.yellow),
                                items: yellow,
                              ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Text(
                                'Totale: $total farmaci da reintegrare',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
      floatingActionButton: !_loading && total > 0
          ? FloatingActionButton.extended(
              onPressed: _showPdfOptions,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Esporta PDF'),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  Widget _emptyState() {
    // Distingue "non c'è nulla" da "il filtro non seleziona nulla".
    final filterEmpty = _cabinetFilter != null &&
        (_expired.isNotEmpty || _red.isNotEmpty || _yellow.isNotEmpty);
    if (filterEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_alt_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            const Text(
              'Nessun armadietto selezionato',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _cabinetFilter = null),
              child: const Text('Mostra tutti gli armadietti'),
            ),
          ],
        ),
      );
    }
    return EmptyState(
      image: 'tutto_in_ordine.png',
      title: 'Tutto in ordine',
      message: 'Nessun farmaco scaduto o in scadenza nei prossimi '
          '${_monthsLabel(_yellowMonths)}.',
    );
  }
}

/// Barra in cima con i due selettori di soglia.
class _ThresholdBar extends StatelessWidget {
  final int redMonths;
  final int yellowMonths;
  final ValueChanged<int> onRedChanged;
  final ValueChanged<int> onYellowChanged;

  const _ThresholdBar({
    required this.redMonths,
    required this.yellowMonths,
    required this.onRedChanged,
    required this.onYellowChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: _ThresholdDropdown(
                label: 'Rosso',
                dotColor: AppColors.expiring,
                value: redMonths,
                options: const [1, 2],
                onChanged: onRedChanged,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ThresholdDropdown(
                label: 'Giallo',
                dotColor: Colors.amber.shade700,
                value: yellowMonths,
                options: const [3, 4, 5, 6],
                onChanged: onYellowChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThresholdDropdown extends StatelessWidget {
  final String label;
  final Color dotColor;
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _ThresholdDropdown({
    required this.label,
    required this.dotColor,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text('$label:', style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Expanded(
          child: DropdownButton<int>(
            value: value,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: options
                .map((m) => DropdownMenuItem(
                      value: m,
                      child: Text(m == 1 ? '1 mese' : '$m mesi'),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null && v != value) onChanged(v);
            },
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;

  /// Tinta viva per icona e sfondi; [textColor] per le scritte, leggibile.
  final Color color;
  final Color textColor;
  final IconData icon;
  final List<_RestockItem> items;

  const _Section({
    required this.title,
    required this.color,
    required this.textColor,
    required this.icon,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('dd/MM/yyyy');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: color.withValues(alpha: 0.1),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(
                '$title (${items.length})',
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
        ...items.map((item) {
          final med = item.medicine;
          return ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 16,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Text(
                'x${med.quantity}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
            title:
                Text(med.name, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(item.cabinetName),
            trailing: Text(
              df.format(med.expirationDate),
              style: TextStyle(color: textColor, fontWeight: FontWeight.w500),
            ),
          );
        }),
      ],
    );
  }
}
