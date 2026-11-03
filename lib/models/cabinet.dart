import 'dart:math';

class Cabinet {
  final int? id;
  final String name;
  final int position;
  final String syncCode;
  int medicineCount;
  DateTime? nearestExpiry;

  Cabinet({
    this.id,
    required this.name,
    required this.position,
    required this.syncCode,
    this.medicineCount = 0,
    this.nearestExpiry,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'position': position,
        'sync_code': syncCode,
      };

  factory Cabinet.fromMap(Map<String, dynamic> map) => Cabinet(
        id: map['id'] as int,
        name: map['name'] as String,
        position: map['position'] as int,
        syncCode: map['sync_code'] as String,
      );

  static String generateSyncCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
