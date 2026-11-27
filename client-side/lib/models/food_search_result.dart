/// Source of the found food – distinguishes which table the result comes from.
enum FoodSource {
  /// Food from the catalog (food.db → Food table)
  catalog,

  /// User's custom food (user.db → CustomFood table)
  custom,
}

/// Unified food search result.
///
/// Contains everything needed for displaying in the results list and for pre-filling
/// the "Log food" form (thus also for writing to [DiaryEntry]).
class FoodSearchResult {
  /// Record ID in the source table.
  final int id;

  /// Food name.
  final String name;

  /// Source – from catalog or custom.
  final FoodSource source;

  /// Calories per 100 g / 100 ml.
  final double kcalPer100;

  /// Protein per 100 g / 100 ml.
  final double proteinPer100;

  /// Carbohydrates per 100 g / 100 ml.
  final double carbsPer100;

  /// Fat per 100 g / 100 ml.
  final double fatPer100;

  /// Default food unit ('g' or 'ml').
  final String unit;

  /// EAN code (may be an empty string).
  final String ean;

  const FoodSearchResult({
    required this.id,
    required this.name,
    required this.source,
    required this.kcalPer100,
    required this.proteinPer100,
    required this.carbsPer100,
    required this.fatPer100,
    this.unit = 'g',
    this.ean = '',
  });

  /// Calculates actual nutritional values for the given amount.
  ///
  /// Returns a map with keys: `kcal`, `protein_g`, `carbs_g`, `fat_g`.
  Map<String, double> nutritionFor(double amount) {
    final factor = amount / 100.0;
    return {
      'kcal': kcalPer100 * factor,
      'protein_g': proteinPer100 * factor,
      'carbs_g': carbsPer100 * factor,
      'fat_g': fatPer100 * factor,
    };
  }

  @override
  String toString() =>
      'FoodSearchResult(id: $id, name: $name, source: $source, kcal/100: $kcalPer100)';
}
