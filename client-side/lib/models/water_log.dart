class WaterLog {
  final int? id;
  final double amountMl; // Objem v ml (např. 250.0)
  final String date;     // Datum ve formátu 'YYYY-MM-DD'

  WaterLog({
    this.id,
    required this.amountMl,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'amount_ml': amountMl,
      'date': date,
    };
  }

  factory WaterLog.fromMap(Map<String, dynamic> map) {
    return WaterLog(
      id: map['id'] as int?,
      amountMl: (map['amount_ml'] as num).toDouble(),
      date: map['date'] as String,
    );
  }

  WaterLog copyWith({
    int? id,
    double? amountMl,
    String? date,
  }) {
    return WaterLog(
      id: id ?? this.id,
      amountMl: amountMl ?? this.amountMl,
      date: date ?? this.date,
    );
  }
}