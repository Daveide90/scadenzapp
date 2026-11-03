import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/medicine.dart';
import '../utils/expiry_utils.dart';

/// Modifica di un farmaco già salvato: nome, quantità, scadenza, dosaggio e
/// lotto (che serve proprio nei ritiri). Restituisce il farmaco modificato,
/// o null se si annulla.
Future<Medicine?> showMedicineEditDialog(BuildContext context, Medicine m) =>
    showDialog<Medicine>(
      context: context,
      builder: (_) => MedicineEditDialog(medicine: m),
    );

class MedicineEditDialog extends StatefulWidget {
  final Medicine medicine;

  const MedicineEditDialog({super.key, required this.medicine});

  @override
  State<MedicineEditDialog> createState() => _MedicineEditDialogState();
}

class _MedicineEditDialogState extends State<MedicineEditDialog> {
  late final _name = TextEditingController(text: widget.medicine.name);
  late final _qty =
      TextEditingController(text: widget.medicine.quantity.toString());
  late final _dosage = TextEditingController(text: widget.medicine.dosage ?? '');
  late final _lot = TextEditingController(text: widget.medicine.lot ?? '');
  late DateTime _date = widget.medicine.expirationDate;

  @override
  void dispose() {
    // Qui e non in whenComplete: il dialogo li usa fino alla fine
    // dell'animazione di chiusura.
    _name.dispose();
    _qty.dispose();
    _dosage.dispose();
    _lot.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final current = int.tryParse(_qty.text) ?? 1;
    if (current + delta >= 1) _qty.text = (current + delta).toString();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: clampToPickable(_date),
      firstDate: firstPickableDate,
      lastDate: lastPickableDate,
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _save() {
    final name = _name.text.trim();
    final qty = int.tryParse(_qty.text) ?? 0;
    if (name.isEmpty || qty < 1) return;
    String? orNull(String s) => s.trim().isEmpty ? null : s.trim();
    final m = widget.medicine;
    // Costruito per intero e non con copyWith: copyWith non sa svuotare un
    // campo (un lotto cancellato tornerebbe quello di prima).
    Navigator.pop(
      context,
      Medicine(
        id: m.id,
        cabinetId: m.cabinetId,
        name: name,
        expirationDate: _date,
        quantity: qty,
        addedAt: m.addedAt,
        form: m.form,
        dosage: orNull(_dosage.text),
        unit: m.unit,
        lot: orNull(_lot.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    return AlertDialog(
      title: const Text('Modifica farmaco'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Nome'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Quantità: '),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Una confezione in meno',
                  onPressed: () => _step(-1),
                ),
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _qty,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(counterText: ''),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Una confezione in più',
                  onPressed: () => _step(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: Text('${two(_date.day)}/${two(_date.month)}/${_date.year}'),
              onPressed: _pickDate,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dosage,
              decoration: const InputDecoration(labelText: 'Dosaggio'),
            ),
            TextField(
              controller: _lot,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Lotto'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        FilledButton(onPressed: _save, child: const Text('Salva')),
      ],
    );
  }
}
