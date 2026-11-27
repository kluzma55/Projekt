/// Amount unit of a diary entry.
enum Unit {
  g,
  ml;

  /// Creates [Unit] from a string; returns [Unit.g] for an unknown value.
  static Unit fromString(String? value) {
    if (value == null) return Unit.g;
    return Unit.values.firstWhere(
      (u) => u.name == value.trim().toLowerCase(),
      orElse: () => Unit.g,
    );
  }

  /// Text representation for saving to DB and displaying in UI ('g' or 'ml').
  String get displayName => name;
}

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

  /// ID from user.db (CustomFood table). Null if it is a food from the catalog.
  final int? customFoodId;

  /// ID from user.db (CustomMeal table). Null if it is not a custom meal.
  final int? mealId;

  final String foodName;

  /// Amount entered by the user (in [unit]).
  final double amount;

  /// Amount unit – g or ml.
  final Unit unit;

  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  /// If [unit] == [Unit.ml] and this field is true, the amount is
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
    Unit? unit,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.isFluidIntake = false,
    String? mealType,
    required this.date,
  })  : unit = unit ?? Unit.g,
        mealType = (mealType != null && mealType.trim().isNotEmpty)
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
      'unit': unit.name,
      'kcal': kcal,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
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
      unit: Unit.fromString(map['unit'] as String?),
      kcal: (map['kcal'] as num).toDouble(),
      proteinG: (map['protein_g'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num).toDouble(),
      fatG: (map['fat_g'] as num).toDouble(),
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
    Unit? unit,
    double? kcal,
    double? proteinG,
    double? carbsG,
    double? fatG,
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
      unit: unit ?? this.unit,
      kcal: kcal ?? this.kcal,
      proteinG: proteinG ?? this.proteinG,
      carbsG: carbsG ?? this.carbsG,
      fatG: fatG ?? this.fatG,
      isFluidIntake: isFluidIntake ?? this.isFluidIntake,
      mealType: mealType ?? this.mealType,
      date: date ?? this.date,
    );
  }
}
