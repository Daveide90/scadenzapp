import 'dart:async';

import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/medicine.dart';
import '../services/notification_service.dart';

class MedicineProvider extends ChangeNotifier {
  final _db = DatabaseHelper();
  final _notifications = NotificationService();
  List<Medicine> _medicines = [];

  /// Callback per segnalare a CabinetProvider che i dati sono cambiati
  VoidCallback? onDataChanged;

  List<Medicine> get medicines => _medicines;

  Future<void> loadMedicines(int cabinetId) async {
    _medicines = await _db.getMedicinesByCabinet(cabinetId);
    notifyListeners();
  }

  Future<void> addMedicine(Medicine medicine) async {
    await _db.insertMedicine(medicine);
    // Senza await e senza errori: il farmaco è già salvato, gli avvisi non
    // devono far credere il contrario (e far salvare un doppione).
    unawaited(_notifications.rescheduleAll());
    onDataChanged?.call();
    await loadMedicines(medicine.cabinetId);
  }

  Future<void> updateMedicine(Medicine medicine) async {
    await _db.updateMedicine(medicine);
    unawaited(_notifications.rescheduleAll());
    onDataChanged?.call();
    await loadMedicines(medicine.cabinetId);
  }

  Future<void> deleteMedicine(int id, int cabinetId) async {
    await _db.deleteMedicine(id);
    unawaited(_notifications.rescheduleAll());
    onDataChanged?.call();
    await loadMedicines(cabinetId);
  }
}
