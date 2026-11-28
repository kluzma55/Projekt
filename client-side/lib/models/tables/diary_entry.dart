class DiaryEntry {
  static const String breakfast = 'Snídaně';
  static const String morningSnack = 'Dopolední svačina';
  static const String lunch = 'Oběd';
  static const String afternoonSnack = 'Odpolední svačina';
  static const String dinner = 'Večeře';
  static const String other = 'Ostatní';

  static const List<String> allowedMealTypes = [
    breakfast,
    morningSnack,
    lunch,
    afternoonSnack,
    dinner,
    other,
  ];

  final int? id;

  /// ID from food.db (Food table). It is 0 if it is a CustomFood.
  final int foodId;

  /// ID from app.db (CustomFood table). Null if it is a food from the catalog.
  final int? customFoodId;

  /// ID from app.db (CustomMeal table). Null if it is not a custom meal.
  final int? mealId;

  final String foodName;

  /// Amount entered by the user (in the food's predefined unit: g or ml).
  final double amount;

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double sugarsG;
  final double fatG;
  final double saturatedFatG;
  final double fibersG;
  final double saltG;

  /// If the food's unit is 'ml' and this field is true, [amount] is
  /// counted toward daily fluid intake (Hydration).
  final bool isFluidIntake;

  final String mealType;
  final String date; // YYYY-MM-DD

  DiaryEntry({
    this.id,
    required this.foodId,
    this.customFoodId,
    this.mealId,
    required this.foodName,
    required this.amount,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    this.sugarsG = 0.0,
    required this.fatG,
    this.saturatedFatG = 0.0,
    this.fibersG = 0.0,
    this.saltG = 0.0,
    this.isFluidIntake = false,
    String? mealType,
    required this.date,
  }) : mealType = (mealType != null && mealType.trim().isNotEmpty)
            ? mealType
            : other;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'food_id': foodId,
      'custom_food_id': customFoodId,
      'meal_id': mealId,
      'food_name': foodName,
      'amount': amount,
      'kcal': kcal,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'sugars_g': sugarsG,
      'fat_g': fatG,
      'saturated_fat_g': saturatedFatG,
      'fibers_g': fibersG,
      'salt_g': saltG,
      'is_fluid_intake': isFluidIntake ? 1 : 0,
      'meal_type': mealType,
      'date': date,
    };
  }

  factory DiaryEntry.fromMap(Map<String, dynamic> map) {
    final rawMealType = map['meal_type'] as String?;

    return DiaryEntry(
      id: map['id'] as int?,
      foodId: map['food_id'] as int,
      customFoodId: map['custom_food_id'] as int?,
      mealId: map['meal_id'] as int?,
      foodName: map['food_name'] as String,
      amount: (map['amount'] as num).toDouble(),
      kcal: (map['kcal'] as num).toDouble(),
      proteinG: (map['protein_g'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num).toDouble(),
      sugarsG: (map['sugars_g'] as num? ?? 0).toDouble(),
      fatG: (map['fat_g'] as num).toDouble(),
      saturatedFatG: (map['saturated_fat_g'] as num? ?? 0).toDouble(),
      fibersG: (map['fibers_g'] as num? ?? 0).toDouble(),
      saltG: (map['salt_g'] as num? ?? 0).toDouble(),
      isFluidIntake: (map['is_fluid_intake'] as int? ?? 0) == 1,
      mealType: (rawMealType != null && rawMealType.isNotEmpty)
          ? rawMealType
          : other,
      date: map['date'] as String,
    );
  }

  DiaryEntry copyWith({
    int? id,
    int? foodId,
    int? customFoodId,
    int? mealId,
    String? foodName,
    double? amount,
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? sugarsG,
    double? fatG,
    double? saturatedFatG,
    double? fibersG,
    double? saltG,
    bool? isFluidIntake,
    String? mealType,
    String? date,
  }) {
    return DiaryEntry(
      id: id ?? this.id,
      foodId: foodId ?? this.foodId,
      customFoodId: customFoodId ?? this.customFoodId,
      mealId: mealId ?? this.mealId,
      foodName: foodName ?? this.foodName,
      amount: amount ?? this.amount,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      carbsG: carbsG ?? this.carbsG,
      sugarsG: sugarsG ?? this.sugarsG,
      fatG: fatG ?? this.fatG,
      saturatedFatG: saturatedFatG ?? this.saturatedFatG,
      fibersG: fibersG ?? this.fibersG,
      saltG: saltG ?? this.saltG,
      isFluidIntake: isFluidIntake ?? this.isFluidIntake,
      mealType: mealType ?? this.mealType,
      date: date ?? this.date,
    );
  }
}
