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
  final int foodId;
  final int? customFoodId; // Odkaz do user.db -> CustomFood (pokud jde o vlastní potravinu)
  final int? mealId; // Odkaz do user.db -> CustomMeal (pokud jde o vlastní jídlo)
  final String foodName;
  final double amountGrams;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double waterMl;
  final String mealType; //snídaně, dopolední svačina, oběd,...
  
  DiaryEntry({
    this.id,
    required this.foodId,
    this.customFoodId,
    this.mealId,
    required this.foodName,
    required this.amountGrams,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    this.waterMl = 0.0,
    String? mealType,
  }) : mealType = (mealType != null && mealType.trim(). isNotEmpty)
        ? mealType
        : other; //Automaticky doplní "Ostatní", pokud uživatel nic nevybere


  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'food_id': foodId,
      'custom_food_id': customFoodId,
      'meal_id': mealId,
      'food_name': foodName,
      'amount_grams': amountGrams,
      'kcal': kcal,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
      'water_ml': waterMl,
      'meal_type': mealType,
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
      amountGrams: (map['amount_grams'] as num).toDouble(),
      kcal: (map['kcal'] as num).toDouble(),
      proteinG: (map['protein_g'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num).toDouble(),
      fatG: (map['fat_g'] as num).toDouble(),
      waterMl: (map['water_ml'] as num?)?.toDouble()?? 0.0,
      mealType: (rawMealType != null && rawMealType.isNotEmpty)
          ? rawMealType
          : other,
    );
  }
}