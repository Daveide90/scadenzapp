import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/cabinet.dart';
import '../models/medicine.dart';
import '../providers/medicine_provider.dart';
import '../widgets/empty_state.dart';
import '../widgets/medicine_edit_dialog.dart';
import '../widgets/medicine_tile.dart';
import 'cabinet_check_screen.dart';
import 'scan_screen.dart';

class CabinetScreen extends StatefulWidget {
  final Cabinet cabinet;

  const CabinetScreen({super.key, required this.cabinet});

  @override
  State<CabinetScreen> createState() => _CabinetScreenState();
}

class _CabinetScreenState extends State<CabinetScreen> {
  @override
  void initState() {
    super.initState();
    context.read<MedicineProvider>().loadMedicines(widget.cabinet.id!);
  }

  Future<void> _showEditDialog(Medicine medicine) async {
    final updated = await showMedicineEditDialog(context, medicine);
    if (updated == null || !mounted) return;
    await context.read<MedicineProvider>().updateMedicine(updated);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cabinet.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined),
            tooltip: 'Controlla questo armadietto',
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => CabinetCheckScreen(cabinet: widget.cabinet),
                ),
              );
              if (context.mounted) {
                context.read<MedicineProvider>().loadMedicines(widget.cabinet.id!);
              }
            },
          ),
        ],
      ),
      body: Consumer<MedicineProvider>(
        builder: (context, provider, _) {
          if (provider.medicines.isEmpty) {
            return const EmptyState(
              image: 'armadietto_vuoto.png',
              title: 'Armadietto vuoto',
              message: 'Premi il pulsante fotocamera per aggiungere il primo '
                  'farmaco: inquadra la confezione e fa quasi tutto da solo.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: provider.medicines.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final medicine = provider.medicines[index];
              return MedicineTile(
                medicine: medicine,
                onTap: () => _showEditDialog(medicine),
                onDelete: () {
                  context
                      .read<MedicineProvider>()
                      .deleteMedicine(medicine.id!, widget.cabinet.id!);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final provider = context.read<MedicineProvider>();
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ScanScreen(cabinetId: widget.cabinet.id!),
            ),
          );
          if (mounted) {
            provider.loadMedicines(widget.cabinet.id!);
          }
        },
        child: const Icon(Icons.camera_alt),
      ),
    );
  }
}
