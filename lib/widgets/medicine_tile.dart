import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/medicine.dart';
import '../utils/expiry_utils.dart';

class MedicineTile extends StatelessWidget {
  final Medicine medicine;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const MedicineTile({
    super.key,
    required this.medicine,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final expiryColor = getExpiryColor(medicine.expirationDate);
    final expiryText = getExpiryTextColor(medicine.expirationDate);
    final expiryLabel = getExpiryLabel(medicine.expirationDate);

    return Dismissible(
      key: Key('medicine_${medicine.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Elimina farmaco'),
            content: Text('Eliminare "${medicine.name}"?'),
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
      },
      onDismissed: (_) => onDelete(),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 4,
          height: 48,
          decoration: BoxDecoration(
            color: expiryColor,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(
          medicine.name,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap e non Row: con i caratteri grandi data ed etichetta vanno
            // a capo invece di uscire dallo schermo.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 2,
              children: [
                Icon(Icons.event, size: 14, color: expiryColor),
                Text(
                  DateFormat('dd/MM/yyyy').format(medicine.expirationDate),
                  style:
                      TextStyle(color: expiryText, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 4),
                Text(
                  expiryLabel,
                  style: TextStyle(
                    color: expiryText,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            // Il lotto compare solo quando c'è: serve per i ritiri di lotto.
            if (medicine.lot != null && medicine.lot!.isNotEmpty)
              Text(
                'Lotto ${medicine.lot}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'x${medicine.quantity}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}
