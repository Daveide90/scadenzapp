class Medicine {
  final int? id;
  final int cabinetId;
  final String name;
  final DateTime expirationDate;
  final int quantity;
  final DateTime addedAt;
  final String? form;
  final String? dosage;
  final String? unit;

  /// Numero di lotto: letto dal Data Matrix della confezione oppure
  /// digitato. Serve a rispondere ai ritiri di lotto.
  final String? lot;

  Medicine({
    this.id,
    required this.cabinetId,
    required this.name,
    required this.expirationDate,
    this.quantity = 1,
    DateTime? addedAt,
    this.form,
    this.dosage,
    this.unit,
    this.lot,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'cabinet_id': cabinetId,
        'name': name,
        'expiration_date':
            '${expirationDate.year}-${expirationDate.month.toString().padLeft(2, '0')}-${expirationDate.day.toString().padLeft(2, '0')}',
        'quantity': quantity,
        'added_at': addedAt.toIso8601String(),
        'form': form,
        'dosage': dosage,
        'unit': unit,
        'lot': lot,
      };

  factory Medicine.fromMap(Map<String, dynamic> map) => Medicine(
        id: map['id'] as int,
        cabinetId: map['cabinet_id'] as int,
        name: map['name'] as String,
        expirationDate: DateTime.parse(map['expiration_date'] as String),
        quantity: map['quantity'] as int,
        addedAt: DateTime.parse(map['added_at'] as String),
        form: map['form'] as String?,
        dosage: map['dosage'] as String?,
        unit: map['unit'] as String?,
        // I backup creati prima della v1.3 non hanno la colonna lotto.
        lot: map['lot'] as String?,
      );

  Medicine copyWith({
    int? id,
    int? cabinetId,
    String? name,
    DateTime? expirationDate,
    int? quantity,
    String? form,
    String? dosage,
    String? unit,
    String? lot,
  }) =>
      Medicine(
        id: id ?? this.id,
        cabinetId: cabinetId ?? this.cabinetId,
        name: name ?? this.name,
        expirationDate: expirationDate ?? this.expirationDate,
        quantity: quantity ?? this.quantity,
        addedAt: addedAt,
        form: form ?? this.form,
        dosage: dosage ?? this.dosage,
        unit: unit ?? this.unit,
        lot: lot ?? this.lot,
      );
}
