import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../theme/app_theme.dart';

/// Gestione dei farmaci aggiunti manualmente (non presenti nel database AIFA).
/// Vengono salvati automaticamente quando l'operatore inserisce un farmaco
/// sconosciuto, e da qui si possono rivedere, aggiungere o rimuovere. Migliorano
/// il riconoscimento nelle scansioni successive.
class CustomMedicinesScreen extends StatefulWidget {
  const CustomMedicinesScreen({super.key});

  @override
  State<CustomMedicinesScreen> createState() => _CustomMedicinesScreenState();
}

class _CustomMedicinesScreenState extends State<CustomMedicinesScreen> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _db.getCustomMedicines();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _subtitle(Map<String, dynamic> m) {
    final parts = <String>[];
    final dosage = (m['dosage'] as String?)?.trim();
    final unit = (m['unit'] as String?)?.trim();
    final form = (m['form'] as String?)?.trim();
    if (dosage != null && dosage.isNotEmpty) {
      parts.add(unit != null && unit.isNotEmpty ? '$dosage $unit' : dosage);
    }
    if (form != null && form.isNotEmpty) parts.add(form);
    return parts.join(' · ');
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rimuovi dal database'),
        content: Text(
          'Rimuovere "${m['name']}" dai farmaci personalizzati?\n\n'
          'I farmaci già inseriti negli armadietti NON vengono toccati: '
          'sparisce solo dai suggerimenti di scansione.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Rimuovi'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteCustomMedicine(m['id'] as int);
      await _load();
    }
  }

  Future<void> _showAddDialog() async {
    final added = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddCustomMedicineDialog(),
    );
    if (added == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Farmaci personalizzati')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: AppColors.primary.withValues(alpha: 0.08),
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 18, color: Colors.grey.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Farmaci non presenti nel database AIFA, aggiunti a mano. '
                          'Migliorano il riconoscimento nelle scansioni.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _items.isEmpty
                      ? _emptyState()
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final m = _items[i];
                            final sub = _subtitle(m);
                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: AppColors.mint,
                                child: Icon(Icons.medication,
                                    color: AppColors.primary),
                              ),
                              title: Text(
                                m['name'] as String,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: sub.isEmpty ? null : Text(sub),
                              trailing: IconButton(
                                icon: Icon(Icons.delete_outline,
                                    color: Colors.red.shade400),
                                tooltip: 'Rimuovi',
                                onPressed: () => _delete(m),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        icon: const Icon(Icons.add),
        label: const Text('Aggiungi'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.medication_outlined, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('Nessun farmaco personalizzato',
              style: TextStyle(fontSize: 17, color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          Text(
            'Verranno aggiunti automaticamente quando inserisci\n'
            'un farmaco non riconosciuto, oppure aggiungili a mano.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}

/// Dialog per aggiungere a mano un farmaco personalizzato. È uno StatefulWidget
/// dedicato così i controller vengono disposti correttamente.
class _AddCustomMedicineDialog extends StatefulWidget {
  const _AddCustomMedicineDialog();

  @override
  State<_AddCustomMedicineDialog> createState() =>
      _AddCustomMedicineDialogState();
}

class _AddCustomMedicineDialogState extends State<_AddCustomMedicineDialog> {
  final _name = TextEditingController();
  final _dosage = TextEditingController();
  final _unit = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _unit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return; // anti doppio-tap
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci il nome del farmaco')),
      );
      return;
    }
    setState(() => _saving = true);
    final dosage = _dosage.text.trim();
    final unit = _unit.text.trim();
    await DatabaseHelper().insertCustomMedicine({
      'name': name.toUpperCase(),
      'active_ingredient': null,
      'form': null,
      'dosage': dosage.isNotEmpty ? dosage : null,
      'unit': unit.isNotEmpty ? unit : null,
      'created_at': DateTime.now().toIso8601String(),
    });
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuovo farmaco personalizzato'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            maxLength: 80,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'Nome *',
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _dosage,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'Dosaggio',
                    hintText: 'es. 500',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _unit,
                  maxLength: 10,
                  decoration: const InputDecoration(
                    labelText: 'Unità',
                    hintText: 'mg',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Aggiungi'),
        ),
      ],
    );
  }
}
