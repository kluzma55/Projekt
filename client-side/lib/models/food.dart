class Food {
  final int? id;
  final String ean;
  final String name;
  final String unit; //'g' nebo 'ml'
  final String imagePath;
  final double kcalPer100;
  final double proteinG;
  final double carbsG;
  final double sugarsG;
  final double fatG;
  final double saturatedFatG;
  final double fibersG;
  final double saltG;
  final bool isUsed; //true, pokud byla již použita
  
  Food({
    this.id,
    this.ean = '',
    required this.name,
    this.unit = 'g',
    this.imagePath = '',
    required this.kcalPer100,
    required this.proteinG,
    required this.carbsG,
    required this.sugarsG,
    required this.fatG,
    required this.saturatedFatG,
    required this.fibersG,
    required this.saltG,
    this.isUsed = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'ean': ean,
      'name': name,
      'unit': unit,
      'image_path': imagePath,
      'kcal_per_100': kcalPer100,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'sugars_g': sugarsG,
      'fat_g': fatG,
      'saturated_fat_g': saturatedFatG,
      'fibers_g': fibersG,
      'salt_g': saltG,
      'is_used': isUsed ? 1 : 0,
    };
  }

  factory Food.fromMap(Map<String, dynamic> map) {
    return Food(
      id: map['id'] as int?,
      ean: (map['ean'] as String?) ?? '',
      name: map['name'] as String,
      unit: (map['unit'] as String?) ?? 'g',
      imagePath: (map['image_path'] as String?) ?? '',
      kcalPer100: (map['kcal_per_100'] as num).toDouble(),
      proteinG: (map['protein_g'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num).toDouble(),
      sugarsG: (map['sugars_g'] as num).toDouble(),
      fatG: (map['fat_g'] as num).toDouble(),
      saturatedFatG: (map['saturated_fat_g'] as num).toDouble(),
      fibersG: (map['fibers_g'] as num).toDouble(),
      saltG: (map['salt_g'] as num).toDouble(),
      isUsed: (map['is_used'] as int? ?? 0) == 1,
    );
  }

  Food copyWith({
    int? id,
    String? ean,
    String? name,
    String? unit,
    String? imagePath,
    double? kcalPer100,
    double? proteinG,
    double? carbsG,
    double? sugarsG,
    double? fatG,
    double? saturatedFatG,
    double? fibersG,
    double? saltG,
    bool? isUsed,
  }) {
    return Food(
      id: id ?? this.id,
      ean: ean ?? this.ean,
      name: name ?? this.name,
      unit: unit ?? this.unit,
      imagePath: imagePath ?? this.imagePath,
      kcalPer100: kcalPer100 ?? this.kcalPer100,
      proteinG: proteinG ?? this.proteinG,
      carbsG: carbsG ?? this.carbsG,
      sugarsG: sugarsG ?? this.sugarsG,
      fatG: fatG ?? this.fatG,
      saturatedFatG: saturatedFatG ?? this.saturatedFatG,
      fibersG: fibersG ?? this.fibersG,
      saltG: saltG ?? this.saltG,
      isUsed: isUsed ?? this.isUsed,
    );
  }
}