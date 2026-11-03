import 'dart:async';

import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import '../models/cabinet.dart';
import '../services/notification_service.dart';

class CabinetProvider extends ChangeNotifier {
  final _db = DatabaseHelper();
  List<Cabinet> _cabinets = [];
  bool _needsReload = true;

  /// true se l'ultimo caricamento è fallito (es. apertura DB lanciata): la home
  /// lo legge per mostrare un messaggio di errore/riprova invece di una UI vuota.
  bool loadError = false;

  List<Cabinet> get cabinets => _cabinets;

  /// Ricarica solo se i dati sono cambiati
  Future<void> loadCabinetsIfNeeded() async {
    if (!_needsReload) return;
    await loadCabinets();
  }

  Future<void> loadCabinets() async {
    try {
      _cabinets = await _db.getCabinetsWithStats();
      _needsReload = false;
      loadError = false;
    } catch (_) {
      // Apertura DB fallita: NON svuotare _cabinets (mantieni l'ultimo valore noto),
      // segnala l'errore e richiedi una ricarica al prossimo tentativo.
      loadError = true;
      _needsReload = true;
    }
    notifyListeners();
  }

  void _markDirty() => _needsReload = true;

  /// Chiamato da MedicineProvider quando i dati farmaci cambiano
  void markNeedsReload() => _needsReload = true;

  Future<void> renameCabinet(int id, String newName) async {
    await _db.updateCabinetName(id, newName);
    _markDirty();
    await loadCabinets();
  }

  Future<int> createCabinet(String name) async {
    final id = await _db.createCabinet(name);
    _markDirty();
    await loadCabinets();
    return id;
  }

  Future<void> deleteCabinet(int id) async {
    await _db.deleteCabinet(id);
    // I farmaci se ne vanno a cascata: anche i loro avvisi.
    unawaited(NotificationService().rescheduleAll());
    _markDirty();
    await loadCabinets();
  }
}
