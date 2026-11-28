import '../database/food_database.dart';
import '../database/user_database.dart';
import '../models/in_memory/food_search_result.dart';
import 'search_service.dart';

/// Specialized search service for foods.
///
/// Combines results from:
/// - [FoodDatabase] (food.db → Food table) – catalog foods
/// - [UserDatabase] (user.db → CustomFood table) – user's custom foods
///
/// Internally uses the generic [SearchService], so filtering and sorting logic
/// can be easily extended or overridden.
///
/// ## Usage example
///
/// ```dart
/// final service = FoodSearchService();
///
/// // Search "jablk" in both databases at once (always pass `limit` in UI!):
/// final results = await service.searchByName('jablk', limit: 50);
///
/// // Search only in custom foods:
/// final custom = await service.searchCustomFoods('tyčinka', limit: 50);
///
/// // Search by EAN (prepared for future scanner):
/// final byEan = await service.searchByEan('8590000000012');
/// ```
class FoodSearchService {
  final SearchService _searchService;

  FoodSearchService({SearchService? searchService})
      : _searchService = searchService ?? SearchService();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Searches [query] in both catalog and custom foods at once.
  ///
  /// Custom foods are sorted first (searched first).
  /// If [query] is empty, returns all records (respecting [limit]).
  ///
  /// IMPORTANT FOR DEVELOPERS / AGENTS:
  /// Always pass a [limit] (e.g., `limit: 50`) when calling this from a UI
  /// screen so broad queries (like `"a"`) don't load the entire food catalog
  /// into memory.
  Future<List<FoodSearchResult>> searchByName(
    String query, {
    int? limit,
  }) async {
    final sources = await _buildNameSources(limit: limit);
    return _searchService.search<FoodSearchResult>(query, sources);
  }

  /// Searches only in catalog (food.db → Food).
  Future<List<FoodSearchResult>> searchCatalogFoods(
    String query, {
    int? limit,
  }) async {
    final source = await _buildCatalogSource(limit: limit);
    return _searchService.searchSingle<FoodSearchResult>(query, source);
  }

  /// Searches only in custom foods (user.db → CustomFood).
  Future<List<FoodSearchResult>> searchCustomFoods(
    String query, {
    int? limit,
  }) async {
    final source = await _buildCustomSource(limit: limit);
    return _searchService.searchSingle<FoodSearchResult>(query, source);
  }

  /// Searches by EAN code in both databases (prepared for EAN scanner).
  ///
  /// Returns an empty list if no food has a matching EAN.
  Future<List<FoodSearchResult>> searchByEan(String ean) async {
    if (ean.trim().isEmpty) return [];
    final sources = await _buildEanSources();
    return _searchService.search<FoodSearchResult>(ean.trim(), sources);
  }

  // ---------------------------------------------------------------------------
  // Factories for SearchSource
  // ---------------------------------------------------------------------------

  static FoodSearchResult _rowToResult(
    Map<String, dynamic> row,
    FoodSource source,
  ) {
    return FoodSearchResult(
      id: row['id'] as int,
      name: row['name'] as String,
      source: source,
      kcalPer100: (row['kcal_per_100'] as num).toDouble(),
      proteinPer100: (row['protein_g'] as num).toDouble(),
      carbsPer100: (row['carbs_g'] as num).toDouble(),
      fatPer100: (row['fat_g'] as num).toDouble(),
      sugarsPer100: (row['sugars_g'] as num?)?.toDouble(),
      saturatedFatPer100: (row['saturated_fat_g'] as num?)?.toDouble(),
      fibersPer100: (row['fibers_g'] as num?)?.toDouble(),
      saltPer100: (row['salt_g'] as num?)?.toDouble(),
      unit: (row['unit'] as String?) ?? 'g',
      ean: (row['ean'] as String?) ?? '',
    );
  }

  Future<SearchSource<FoodSearchResult>> _buildCatalogSource({
    int? limit,
  }) async {
    final db = await FoodDatabase.instance.database;
    return SearchSource<FoodSearchResult>(
      database: db,
      tableName: 'Food',
      searchColumns: const ['name'],
      orderBy: 'is_used DESC, name ASC',
      limit: limit,
      fromRow: (row) => _rowToResult(row, FoodSource.catalog),
    );
  }

  Future<SearchSource<FoodSearchResult>> _buildCustomSource({
    int? limit,
  }) async {
    final db = await UserDatabase.instance.database;
    return SearchSource<FoodSearchResult>(
      database: db,
      tableName: 'CustomFood',
      searchColumns: const ['name'],
      orderBy: 'name ASC',
      limit: limit,
      fromRow: (row) => _rowToResult(row, FoodSource.custom),
    );
  }

  Future<List<SearchSource<FoodSearchResult>>> _buildNameSources({
    int? limit,
  }) async {
    return [
      await _buildCustomSource(limit: limit),
      await _buildCatalogSource(limit: limit),
    ];
  }

  Future<List<SearchSource<FoodSearchResult>>> _buildEanSources() async {
    final foodDb = await FoodDatabase.instance.database;
    final userDb = await UserDatabase.instance.database;

    return [
      SearchSource<FoodSearchResult>(
        database: userDb,
        tableName: 'CustomFood',
        searchColumns: const ['ean'],
        orderBy: 'name ASC',
        limit: 1,
        fromRow: (row) => _rowToResult(row, FoodSource.custom),
      ),
      SearchSource<FoodSearchResult>(
        database: foodDb,
        tableName: 'Food',
        searchColumns: const ['ean'],
        orderBy: 'name ASC',
        limit: 1,
        fromRow: (row) => _rowToResult(row, FoodSource.catalog),
      ),
    ];
  }
}
