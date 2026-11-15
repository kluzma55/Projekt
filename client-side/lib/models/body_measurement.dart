class BodyMeasurement {
  final int? id;
  final String date;             // Datum měření ve formátu 'YYYY-MM-DD'
  final double weightKg;         // Aktuální hmotnost v kg
  final double? bodyFatPercent;  // Volitelné procento tělesného tuku
  final double? muscleMassKg;    // Volitelná svalová hmota v kg

  BodyMeasurement({
    this.id,
    required this.date,
    required this.weightKg,
    this.bodyFatPercent,
    this.muscleMassKg,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'date': date,
      'weight_kg': weightKg,
      'body_fat_percent': bodyFatPercent,
      'muscle_mass_kg': muscleMassKg,
    };
  }

  factory BodyMeasurement.fromMap(Map<String, dynamic> map) {
    return BodyMeasurement(
      id: map['id'] as int?,
      date: map['date'] as String,
      weightKg: (map['weight_kg'] as num).toDouble(),
      bodyFatPercent: (map['body_fat_percent'] as num?)?.toDouble(),
      muscleMassKg: (map['muscle_mass_kg'] as num?)?.toDouble(),
    );
  }

  BodyMeasurement copyWith({
    int? id,
    String? date,
    double? weightKg,
    double? bodyFatPercent,
    double? muscleMassKg,
  }) {
    return BodyMeasurement(
      id: id ?? this.id,
      date: date ?? this.date,
      weightKg: weightKg ?? this.weightKg,
      bodyFatPercent: bodyFatPercent ?? this.bodyFatPercent,
      muscleMassKg: muscleMassKg ?? this.muscleMassKg,
    );
  }
}