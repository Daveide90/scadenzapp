import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/aifa_catalog_service.dart';
import '../utils/aic_utils.dart';
import '../utils/expiry_utils.dart';
import '../theme/app_theme.dart';

class ConfirmSheet extends StatefulWidget {
  final String? initialName;
  final DateTime? initialDate;
  final String? initialForm;
  final String? initialDosage;
  final String? initialUnit;
  final String? initialLot;
  final void Function(String name, DateTime date, int quantity,
      {String? form, String? dosage, String? unit, String? lot}) onSave;

  /// Chiamato quando l'utente modifica a mano il nome (così l'OCR non lo sovrascrive).
  final VoidCallback? onNameEdited;

  /// Chiamato quando l'utente scrive il lotto a mano (così il bollino non lo sovrascrive).
  final VoidCallback? onLotEdited;

  const ConfirmSheet({
    super.key,
    this.initialName,
    this.initialDate,
    this.initialForm,
    this.initialDosage,
    this.initialUnit,
    this.initialLot,
    required this.onSave,
    this.onNameEdited,
    this.onLotEdited,
  });

  @override
  State<ConfirmSheet> createState() => ConfirmSheetState();
}

class ConfirmSheetState extends State<ConfirmSheet> {
  late TextEditingController _nameController;
  late TextEditingController _dateController;
  late TextEditingController _dosageController;
  late TextEditingController _unitController;
  late TextEditingController _lotController;
  DateTime? _selectedDate;
  int _quantity = 1;
  String? _selectedForm;
  bool _showDetails = false;
  bool _saving = false;
  bool _dateEditedByUser = false;

  static const _forms = [
    'compresse',
    'compresse rivestite',
    'compresse effervescenti',
    'capsule',
    'capsule molli',
    'bustine',
    'fiale',
    'gocce',
    'sciroppo',
    'sospensione orale',
    'soluzione orale',
    'soluzione iniettabile',
    'spray',
    'spray nasale',
    'crema',
    'gel',
    'pomata',
    'unguento',
    'supposte',
    'cerotti',
    'collirio',
    'collutorio',
    'granulato',
    'polvere',
    'ovuli',
    'inalatore',
    'aerosol',
    'siringa',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName ?? '');
    _selectedDate = widget.initialDate;
    _dateController = TextEditingController(
      text: _selectedDate != null ? DateFormat('dd/MM/yyyy').format(_selectedDate!) : '',
    );
    _dosageController = TextEditingController(text: widget.initialDosage ?? '');
    _unitController = TextEditingController(text: widget.initialUnit ?? '');
    _lotController = TextEditingController(text: widget.initialLot ?? '');
    _selectedForm = widget.initialForm;
    _showDetails = _selectedForm != null ||
        (widget.initialDosage?.isNotEmpty ?? false) ||
        (widget.initialUnit?.isNotEmpty ?? false) ||
        (widget.initialLot?.isNotEmpty ?? false);
  }

  void updateName(String name) {
    if (_nameController.text.isEmpty && name.isNotEmpty) {
      _nameController.text = name;
    }
  }

  void forceUpdateName(String name) {
    _nameController.text = name;
  }

  /// Data trovata in automatico (OCR o Data Matrix): non sostituisce mai una
  /// data scelta dall'utente, altrimenti l'auto-correzione dell'OCR
  /// rimetterebbe la data sbagliata che l'utente ha appena corretto.
  void updateDate(DateTime date) {
    if (_dateEditedByUser) return;
    _showDate(date);
  }

  /// Data scelta dall'utente (calendario o suggerimento toccato): vale
  /// sempre, e da qui in poi la lettura automatica non la tocca più.
  void setDateByUser(DateTime date) {
    _dateEditedByUser = true;
    _showDate(date);
  }

  void _showDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _dateController.text = DateFormat('dd/MM/yyyy').format(date);
    });
  }

  /// Lotto letto dal Data Matrix: non sovrascrive quello già presente
  /// (se c'è, o l'ha scritto l'utente o l'ha già messo il bollino).
  void updateLot(String lot) {
    if (_lotController.text.isNotEmpty || lot.isEmpty) return;
    setState(() {
      _lotController.text = lot;
      _showDetails = true;
    });
  }

  void updateDetails({String? form, String? dosage, String? unit}) {
    setState(() {
      if (form != null && _selectedForm == null) {
        // Solo se il valore e' nella lista dropdown
        if (_forms.contains(form.toLowerCase())) {
          _selectedForm = form.toLowerCase();
        }
      }
      if (dosage != null && _dosageController.text.isEmpty) _dosageController.text = dosage;
      if (unit != null && _unitController.text.isEmpty) _unitController.text = unit;
      if (_selectedForm != null || _dosageController.text.isNotEmpty) {
        _showDetails = true;
      }
    });
  }

  void reset() {
    setState(() {
      _nameController.clear();
      _dateController.clear();
      _dosageController.clear();
      _unitController.clear();
      _lotController.clear();
      _selectedDate = null;
      _dateEditedByUser = false;
      _quantity = 1;
      _selectedForm = null;
      _showDetails = false;
      _saving = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dateController.dispose();
    _dosageController.dispose();
    _unitController.dispose();
    _lotController.dispose();
    super.dispose();
  }

  /// Se l'utente digita un AIC (9 cifre) nel campo nome, cerca la confezione
  /// nel catalogo AIFA e compila nome, forma, dosaggio e unità.
  Future<void> _maybeLookupAic(String text) async {
    final code = text.trim();
    if (!isAicCandidate(code)) return;
    final med = await AifaCatalogService().lookupAic(code);
    if (!mounted || med == null) return;
    // Nel frattempo l'utente potrebbe aver cambiato il testo
    if (_nameController.text.trim() != code) return;
    setState(() => _nameController.text = med.displayName);
    // L'unità di misura resta vuota: la compila l'utente.
    updateDetails(form: med.appForm, dosage: med.dosage);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('AIC ${med.aic}: ${med.displayName}'),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: clampToPickable(
          _selectedDate ?? DateTime.now().add(const Duration(days: 365))),
      firstDate: firstPickableDate,
      lastDate: lastPickableDate,
    );
    if (picked != null) {
      setDateByUser(picked);
    }
  }

  void _save() {
    if (_saving) return; // anti doppio-tap → niente farmaci duplicati
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome del farmaco')),
      );
      return;
    }
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci la data di scadenza')),
      );
      return;
    }
    final dosage = _dosageController.text.trim();
    final unit = _unitController.text.trim();
    final lot = _lotController.text.trim();
    setState(() => _saving = true);
    widget.onSave(
      name,
      _selectedDate!,
      _quantity,
      form: _selectedForm,
      dosage: dosage.isNotEmpty ? dosage : null,
      unit: unit.isNotEmpty ? unit : null,
      lot: lot.isNotEmpty ? lot : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Nome farmaco *',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.medication),
              counterText: '',
            ),
            textCapitalization: TextCapitalization.sentences,
            // onChanged scatta SOLO per input dell'utente (non per le modifiche
            // programmatiche dell'OCR) → segnala che il nome è stato editato a mano.
            onChanged: (text) {
              widget.onNameEdited?.call();
              _maybeLookupAic(text);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _dateController,
            readOnly: true,
            decoration: const InputDecoration(
              labelText: 'Data scadenza *',
              // La lettura automatica può sbagliare: fa fede la confezione.
              helperText: 'Controlla che sia quella stampata sulla confezione',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.event),
            ),
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          // Toggle dettagli
          InkWell(
            onTap: () => setState(() => _showDetails = !_showDetails),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showDetails ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _showDetails ? 'Nascondi dettagli' : 'Aggiungi dettagli (forma, dosaggio...)',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          if (_showDetails) ...[
            const SizedBox(height: 8),
            // Forma farmaceutica — dropdown
            DropdownButtonFormField<String>(
              value: _selectedForm,
              decoration: const InputDecoration(
                labelText: 'Forma farmaceutica',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category_outlined),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                ..._forms.map((f) => DropdownMenuItem(value: f, child: Text(f))),
              ],
              onChanged: (v) => setState(() => _selectedForm = v),
            ),
            const SizedBox(height: 10),
            // Dosaggio + Unità sulla stessa riga
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _dosageController,
                    decoration: const InputDecoration(
                      labelText: 'Dosaggio',
                      hintText: 'es. 500',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.scale_outlined),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                    keyboardType: TextInputType.text,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _unitController,
                    decoration: const InputDecoration(
                      labelText: 'Unità',
                      hintText: 'es. mg',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Lotto: lo compila il Data Matrix quando c'è, altrimenti si scrive.
            TextField(
              controller: _lotController,
              maxLength: 30,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Lotto',
                hintText: 'dal bollino, o a mano',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code_2),
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              onChanged: (_) => widget.onLotEdited?.call(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Colors.grey),
              const SizedBox(width: 12),
              const Text('Quantità:', style: TextStyle(fontSize: 16)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Una confezione in meno',
                iconSize: 32,
                onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              Text(
                '$_quantity',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Una confezione in più',
                iconSize: 32,
                onPressed:
                    _quantity < 9999 ? () => setState(() => _quantity++) : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('Salva', style: TextStyle(fontSize: 18)),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}
