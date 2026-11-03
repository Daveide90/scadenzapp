import '../utils/expiry_utils.dart';

/// Un controllo periodico di un armadietto: chi l'ha fatto, quando e cosa ha
/// trovato. È la traccia che di solito resta su un modulo cartaceo.
class CabinetCheck {
  CabinetCheck({
    this.id,
    required this.cabinetId,
    required this.operator,
    required this.checkedCount,
    required this.expiredFound,
    required this.expiringFound,
    this.removedCount = 0,
    this.notes,
    DateTime? performedAt,
  }) : performedAt = performedAt ?? DateTime.now();

  final int? id;
  final int cabinetId;
  final DateTime performedAt;

  /// Nome di chi ha eseguito il controllo: finisce nel report.
  final String operator;

  /// Confezioni presenti al momento del controllo.
  final int checkedCount;

  /// Confezioni già scadute trovate.
  final int expiredFound;

  /// Confezioni in scadenza (fascia rossa o gialla) trovate.
  final int expiringFound;

  /// Confezioni rimosse durante il controllo.
  final int removedCount;

  final String? notes;

  /// Un controllo è "regolare" se non ha trovato nulla di scaduto.
  bool get isClear => expiredFound == 0;

  Map<String, dynamic> toMap() => {
        'id': id,
        'cabinet_id': cabinetId,
        'performed_at': performedAt.toIso8601String(),
        'operator': operator,
        'checked_count': checkedCount,
        'expired_found': expiredFound,
        'expiring_found': expiringFound,
        'removed_count': removedCount,
        'notes': notes,
      };

  factory CabinetCheck.fromMap(Map<String, dynamic> map) => CabinetCheck(
        id: map['id'] as int?,
        cabinetId: map['cabinet_id'] as int,
        performedAt: DateTime.parse(map['performed_at'] as String),
        operator: map['operator'] as String,
        checkedCount: (map['checked_count'] as int?) ?? 0,
        expiredFound: (map['expired_found'] as int?) ?? 0,
        expiringFound: (map['expiring_found'] as int?) ?? 0,
        removedCount: (map['removed_count'] as int?) ?? 0,
        notes: map['notes'] as String?,
      );
}

/// Conteggi di un controllo in corso. Le confezioni tolte durante il
/// controllo vengono cancellate subito: contano con la fascia che avevano
/// quando sono state tolte, altrimenti tre scatole scadute tolte
/// finirebbero nel report come «0 scaduti trovati».
class CheckTally {
  int removed = 0;
  int _removedExpired = 0;
  int _removedExpiring = 0;

  void recordRemoval(RestockBand band) {
    removed++;
    if (band == RestockBand.expired) {
      _removedExpired++;
    } else if (band == RestockBand.red || band == RestockBand.yellow) {
      _removedExpiring++;
    }
  }

  /// Le confezioni tolte sono state controllate anche loro.
  int checked({required int verified}) => verified + removed;

  int expiredFound(Iterable<RestockBand> remaining) =>
      remaining.where((b) => b == RestockBand.expired).length + _removedExpired;

  int expiringFound(Iterable<RestockBand> remaining) =>
      remaining
          .where((b) => b == RestockBand.red || b == RestockBand.yellow)
          .length +
      _removedExpiring;
}
