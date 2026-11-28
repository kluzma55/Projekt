class CustomFood {
  final int? id;
  final String ean;
  final String name;
  final String unit; // 'g' or 'ml'
  final double kcalPer100;
  final double proteinG;
  final double carbsG;
  final double sugarsG;
  final double fatG;
  final double saturatedFatG;
  final double fibersG;
  final double saltG;

  CustomFood({
    this.id,
    this.ean = '',
    required this.name,
    this.unit = 'g',
    required this.kcalPer100,
    required this.proteinG,
    required this.carbsG,
    this.sugarsG = 0.0,
    required this.fatG,
    this.saturatedFatG = 0.0,
    this.fibersG = 0.0,
    this.saltG = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'ean': ean,
      'name': name,
      'unit': unit,
      'kcal_per_100': kcalPer100,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'sugars_g': sugarsG,
      'fat_g': fatG,
      'saturated_fat_g': saturatedFatG,
      'fibers_g': fibersG,
      'salt_g': saltG,
    };
  }

  factory CustomFood.fromMap(Map<String, dynamic> map) {
    return CustomFood(
      id: map['id'] as int?,
      ean: (map['ean'] as String?) ?? '',
      name: map['name'] as String,
      unit: (map['unit'] as String?) ?? 'g',
      kcalPer100: (map['kcal_per_100'] as num).toDouble(),
      proteinG: (map['protein_g'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num).toDouble(),
      sugarsG: (map['sugars_g'] as num? ?? 0).toDouble(),
      fatG: (map['fat_g'] as num).toDouble(),
      saturatedFatG: (map['saturated_fat_g'] as num? ?? 0).toDouble(),
      fibersG: (map['fibers_g'] as num? ?? 0).toDouble(),
      saltG: (map['salt_g'] as num? ?? 0).toDouble(),
    );
  }

  CustomFood copyWith({
    int? id,
    String? ean,
    String? name,
    String? unit,
    double? kcalPer100,
    double? proteinG,
    double? carbsG,
    double? sugarsG,
    double? fatG,
    double? saturatedFatG,
    double? fibersG,
    double? saltG,
  }) {
    return CustomFood(
      id: id ?? this.id,
      ean: ean ?? this.ean,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      kcalPer100: kcalPer100 ?? this.kcalPer100,
      proteinG: proteinG ?? this.proteinG,
      carbsG: carbsG ?? this.carbsG,
      sugarsG: sugarsG ?? this.sugarsG,
      fatG: fatG ?? this.fatG,
      saturatedFatG: saturatedFatG ?? this.saturatedFatG,
      fibersG: fibersG ?? this.fibersG,
      saltG: saltG ?? this.saltG,
    );
  }
}