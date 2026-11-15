class CustomMeal {
  final int? id;
  final String name;
  final int totalPortions;

  CustomMeal({
    this.id,
    required this.name,
    required this.totalPortions,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'total_portions': totalPortions,
    };
  }

  factory CustomMeal.fromMap(Map<String, dynamic> map) {
    return CustomMeal(
      id: map['id'] as int?,
      name: map['name'] as String,
      totalPortions: map['total_portions'] as int,
    );
  }
}

class CustomMealIngredient {
  final int? id;
  final int mealId;
  final int? foodId;       // Odkaz do food.db (pokud jde o potravinu z katalogu)
  final int? customFoodId; // Odkaz do user.db -> CustomFood (pokud jde o vlastní potravinu)
  final String foodName;
  final double amountGrams;
  final double kcal;
  final double proteinG;
  final double carbsG;
  final double fatG;

  CustomMealIngredient({
    this.id,
    required this.mealId,
    this.foodId,
    this.customFoodId,
    required this.foodName,
    required this.amountGrams,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'meal_id': mealId,
      'food_id': foodId,
      'custom_food_id': customFoodId,
      'food_name': foodName,
      'amount_grams': amountGrams,
      'kcal': kcal,
      'protein_g': proteinG,
      'carbs_g': carbsG,
      'fat_g': fatG,
    };
  }

  factory CustomMealIngredient.fromMap(Map<String, dynamic> map) {
    return CustomMealIngredient(
      id: map['id'] as int?,
      mealId: map['meal_id'] as int,
      foodId: map['food_id'] as int?,
      customFoodId: map['custom_food_id'] as int?,
      foodName: map['food_name'] as String,
      amountGrams: (map['amount_grams'] as num).toDouble(),
      kcal: (map['kcal'] as num).toDouble(),
      proteinG: (map['protein_g'] as num).toDouble(),
      carbsG: (map['carbs_g'] as num).toDouble(),
      fatG: (map['fat_g'] as num).toDouble(),
    );
  }
}