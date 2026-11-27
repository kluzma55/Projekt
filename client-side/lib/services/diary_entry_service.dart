import '../database/user_database.dart';
import '../models/diary_entry.dart';
import '../models/food_search_result.dart';

/// Error states when validating a diary entry.
enum DiaryEntryError {
  /// No food was selected.
  noFoodSelected,

  /// Amount is zero or negative.
  invalidAmount,

  /// Amount is not a valid number (contains invalid characters).
  invalidAmountFormat,

  /// Date is not in YYYY-MM-DD format.
  invalidDate,

  /// Meal type is not in the allowed list.
  invalidMealType,
}

/// Validation result and optionally constructed diary entry.
class DiaryEntryValidationResult {
  final DiaryEntry? entry;
  final List<DiaryEntryError> errors;

  const DiaryEntryValidationResult({this.entry, required this.errors});

  bool get isValid => errors.isEmpty;
}

/// Service for creating and saving entries in the calorie diary.
///
/// Connects [FoodSearchResult] (selected item from the list) with the form
/// (amount, meal type, date) and performs:
/// 1. Input validation
/// 2. Recalculation of nutritional values by amount
/// 3. Saving the entry to user.db (DiaryEntry table)
///
/// ## Usage example
///
/// ```dart
/// final service = DiaryEntryService();
///
/// final result = await service.saveEntry(
///   selectedFood: searchResult,  // result from FoodSearchService
///   amountText: '150',           // text from TextField
///   unit: Unit.g,
///   mealType: DiaryEntry.breakfast,
///   date: '2026-11-27',
///   isFluidIntake: false,
/// );
///
/// if (result.isValid) {
///   // Entry was saved
/// } else {
///   // Show errors: result.errors
/// }
/// ```
class DiaryEntryService {
  final UserDatabase _userDb;

  DiaryEntryService({UserDatabase? userDatabase})
      : _userDb = userDatabase ?? UserDatabase.instance;

  // ---------------------------------------------------------------------------
  // Validation
  // ---------------------------------------------------------------------------

  /// Validates inputs and builds [DiaryEntry] without saving to DB.
  ///
  /// Use when you want to validate the form before showing a preview or
  /// before saving itself.
  DiaryEntryValidationResult validate({
    required FoodSearchResult? selectedFood,
    required String amountText,
    Unit unit = Unit.g,
    required String mealType,
    required String date,
    bool isFluidIntake = false,
  }) {
    final errors = <DiaryEntryError>[];

    // 1. A food must be selected
    if (selectedFood == null) {
      errors.add(DiaryEntryError.noFoodSelected);
    }

    // 2. Amount validation
    final parsedAmount = _parseAmount(amountText);
    if (parsedAmount == null) {
      errors.add(DiaryEntryError.invalidAmountFormat);
    } else if (parsedAmount <= 0) {
      errors.add(DiaryEntryError.invalidAmount);
    }

    // 3. Date validation
    if (!_isValidDate(date)) {
      errors.add(DiaryEntryError.invalidDate);
    }

    // 4. Meal type validation
    if (!DiaryEntry.allowedMealTypes.contains(mealType)) {
      errors.add(DiaryEntryError.invalidMealType);
    }

    if (errors.isNotEmpty || selectedFood == null || parsedAmount == null) {
      return DiaryEntryValidationResult(errors: errors);
    }

    final entry = _buildEntry(
      food: selectedFood,
      amount: parsedAmount,
      unit: unit,
      mealType: mealType,
      date: date,
      isFluidIntake: isFluidIntake,
    );

    return DiaryEntryValidationResult(entry: entry, errors: const []);
  }

  // ---------------------------------------------------------------------------
  // Saving the entry
  // ---------------------------------------------------------------------------

  /// Validates inputs, recalculates nutritional values, and saves the entry to DB.
  ///
  /// Returns [DiaryEntryValidationResult]:
  /// - If validation fails, [DiaryEntryValidationResult.isValid] is false
  ///   and [DiaryEntryValidationResult.errors] contains the errors.
  /// - If everything succeeds, [DiaryEntryValidationResult.entry]
  ///   contains the saved [DiaryEntry] (with assigned ID from DB).
  Future<DiaryEntryValidationResult> saveEntry({
    required FoodSearchResult? selectedFood,
    required String amountText,
    Unit unit = Unit.g,
    required String mealType,
    required String date,
    bool isFluidIntake = false,
  }) async {
    final validation = validate(
      selectedFood: selectedFood,
      amountText: amountText,
      unit: unit,
      mealType: mealType,
      date: date,
      isFluidIntake: isFluidIntake,
    );

    if (!validation.isValid || validation.entry == null) {
      return validation;
    }

    final id = await _userDb.insertDiaryEntry(validation.entry!);
    final savedEntry = validation.entry!.copyWith(id: id);

    return DiaryEntryValidationResult(entry: savedEntry, errors: const []);
  }

  // ---------------------------------------------------------------------------
  // Recalculation of nutritional values (for UI preview)
  // ---------------------------------------------------------------------------

  /// Recalculates nutritional values for the given amount and selected food.
  ///
  /// Returns null if [selectedFood] is null or [amount] ≤ 0.
  Map<String, double>? recalculate({
    required FoodSearchResult? selectedFood,
    required double amount,
  }) {
    if (selectedFood == null || amount <= 0) return null;
    return selectedFood.nutritionFor(amount);
  }

  // ---------------------------------------------------------------------------
  // Internal helper methods
  // ---------------------------------------------------------------------------

  DiaryEntry _buildEntry({
    required FoodSearchResult food,
    required double amount,
    required Unit unit,
    required String mealType,
    required String date,
    required bool isFluidIntake,
  }) {
    final nutrition = food.nutritionFor(amount);

    return DiaryEntry(
      foodId: food.source == FoodSource.catalog ? food.id : 0,
      customFoodId: food.source == FoodSource.custom ? food.id : null,
      foodName: food.name,
      amount: amount,
      unit: unit,
      kcal: nutrition['kcal']!,
      proteinG: nutrition['protein_g']!,
      carbsG: nutrition['carbs_g']!,
      fatG: nutrition['fat_g']!,
      isFluidIntake: isFluidIntake,
      mealType: mealType,
      date: date,
    );
  }

  /// Attempts to parse text input into a positive number.
  /// Accepts both comma and dot as decimal separator.
  /// Returns null on invalid format.
  double? _parseAmount(String text) {
    final cleaned = text.trim().replaceAll(',', '.');
    return double.tryParse(cleaned);
  }

  /// Verifies that [date] is in YYYY-MM-DD format and is a valid date.
  bool _isValidDate(String date) {
    final regex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!regex.hasMatch(date)) return false;
    try {
      DateTime.parse(date);
      return true;
    } catch (_) {
      return false;
    }
  }
}
