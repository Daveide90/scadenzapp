import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../database/database_helper.dart';
import '../models/cabinet.dart';
import '../models/cabinet_check.dart';
import '../models/medicine.dart';
import '../providers/medicine_provider.dart';
import '../services/settings_service.dart';
import '../utils/expiry_utils.dart';
import '../theme/app_theme.dart';

/// Controllo periodico di un armadietto: si scorrono le confezioni, si
/// spunta quello che si è verificato, si tolgono gli scaduti e si firma
/// col proprio nome. Sostituisce il modulo cartaceo.
class CabinetCheckScreen extends StatefulWidget {
  const CabinetCheckScreen({super.key, required this.cabinet});

  final Cabinet cabinet;

  @override
  State<CabinetCheckScreen> createState() => _CabinetCheckScreenState();
}

class _CabinetCheckScreenState extends State<CabinetCheckScreen> {
  final _db = DatabaseHelper();
  final _settings = SettingsService();
  final _operatorController = TextEditingController();
  final _notesController = TextEditingController();

  final Set<int> _verified = {};
  final _tally = CheckTally();
  int _redMonths = SettingsService.defaultRedMonths;
  int _yellowMonths = SettingsService.defaultYellowMonths;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    context.read<MedicineProvider>().loadMedicines(widget.cabinet.id!);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final name = await _settings.getOperatorName();
    final red = await _settings.getRedMonths();
    final yellow = await _settings.getYellowMonths();
    if (!mounted) return;
    setState(() {
      if (name != null) _operatorController.text = name;
      _redMonths = red;
      _yellowMonths = yellow;
    });
  }

  @override
  void dispose() {
    _operatorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  RestockBand _band(Medicine m) => classifyRestock(
        m.expirationDate,
        redMonths: _redMonths,
        yellowMonths: _yellowMonths,
      );

  Future<void> _removeMedicine(Medicine medicine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Togliere dall\'armadietto?'),
        content: Text(
          '"${medicine.name}" verrà eliminato e conteggiato tra le confezioni '
          'rimosse in questo controllo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Togli'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context
        .read<MedicineProvider>()
        .deleteMedicine(medicine.id!, widget.cabinet.id!);
    if (!mounted) return;
    setState(() {
      _tally.recordRemoval(_band(medicine));
      _verified.remove(medicine.id);
    });
  }

  Future<void> _save(List<Medicine> medicines) async {
    final operator = _operatorController.text.trim();
    if (operator.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scrivi chi ha fatto il controllo')),
      );
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final bands = medicines.map(_band).toList();
    final expired = _tally.expiredFound(bands);
    final expiring = _tally.expiringFound(bands);

    final notes = _notesController.text.trim();
    // Il messenger va preso PRIMA di uscire dalla schermata: dopo il pop
    // questo context non ne ha più uno e la conferma non comparirebbe.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _settings.setOperatorName(operator);
      await _db.insertCabinetCheck(CabinetCheck(
        cabinetId: widget.cabinet.id!,
        operator: operator,
        checkedCount: _tally.checked(verified: _verified.length),
        expiredFound: expired,
        expiringFound: expiring,
        removedCount: _tally.removed,
        notes: notes.isEmpty ? null : notes,
      ));
    } catch (e) {
      // Se il salvataggio fallisce l'utente deve poter riprovare, non
      // restare con un controllo che crede registrato.
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Controllo non salvato, riprova'),
          backgroundColor: AppColors.expired,
          action: SnackBarAction(
            label: 'Dettagli',
            textColor: Colors.white,
            onPressed: () => messenger.showSnackBar(SnackBar(content: Text('$e'))),
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, true);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Controllo registrato'),
        backgroundColor: AppColors.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Controllo · ${widget.cabinet.name}')),
      body: Consumer<MedicineProvider>(
        builder: (context, provider, _) {
          final medicines = provider.medicines;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              TextField(
                controller: _operatorController,
                maxLength: 60,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Controllo eseguito da *',
                  hintText: 'nome e cognome',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.badge_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Data del controllo: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const Divider(height: 28),
              if (medicines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Center(
                    child: Text(
                      'Armadietto vuoto: puoi comunque registrare il controllo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ),
                )
              else ...[
                Text(
                  'Spunta quello che hai verificato (${_verified.length}/${medicines.length})',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                ...medicines.map((m) => _MedicineCheckTile(
                      medicine: m,
                      band: _band(m),
                      checked: _verified.contains(m.id),
                      onChanged: (v) => setState(() {
                        if (v) {
                          _verified.add(m.id!);
                        } else {
                          _verified.remove(m.id);
                        }
                      }),
                      onRemove: () => _removeMedicine(m),
                    )),
                if (_tally.removed > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Confezioni tolte in questo controllo: ${_tally.removed}',
                      style: const TextStyle(
                          color: AppColors.expired, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'anomalie, azioni fatte, segnalazioni…',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _saving
                ? null
                : () => _save(context.read<MedicineProvider>().medicines),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('Registra controllo',
                style: TextStyle(fontSize: 17)),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
          ),
        ),
        ),
      ),
    );
  }
}

class _MedicineCheckTile extends StatelessWidget {
  const _MedicineCheckTile({
    required this.medicine,
    required this.band,
    required this.checked,
    required this.onChanged,
    required this.onRemove,
  });

  final Medicine medicine;
  final RestockBand band;
  final bool checked;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (band) {
      RestockBand.expired => (AppColors.expired, 'scaduto'),
      RestockBand.red => (AppColors.expiring, 'in scadenza'),
      RestockBand.yellow => (Colors.amber.shade700, 'attenzione'),
      RestockBand.none => (Colors.grey.shade600, null),
    };

    return CheckboxListTile(
      value: checked,
      onChanged: (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text(medicine.name, style: const TextStyle(fontSize: 15)),
      subtitle: Row(
        children: [
          Text(
            DateFormat('dd/MM/yyyy').format(medicine.expirationDate),
            style: TextStyle(
                color: restockTextColor(band), fontWeight: FontWeight.w600),
          ),
          if (label != null) ...[
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: restockTextColor(band),
                    fontSize: 12,
                    fontStyle: FontStyle.italic)),
          ],
          if (medicine.lot != null && medicine.lot!.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                'lotto ${medicine.lot}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ],
        ],
      ),
      secondary: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Togli dall\'armadietto',
        color: Colors.grey.shade600,
        onPressed: onRemove,
      ),
    );
  }
}
