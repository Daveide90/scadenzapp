import 'medicine.dart';

/// Un farmaco trovato dalla ricerca, con l'armadietto in cui sta.
class MedicineSearchHit {
  const MedicineSearchHit({required this.medicine, required this.cabinetName});

  final Medicine medicine;
  final String cabinetName;
}
