import 'package:sqflite/sqflite.dart';

/// Description of a single searchable data source.
///
/// [SearchSource] defines:
/// - which database and which table to search in,
/// - by which columns,
/// - how to order results,
/// - how to transform a raw DB row into the desired result type [T].
///
/// Thanks to the generic parameter [T], [SearchService] can be used for any
/// result type – foods, activities, custom meals, etc.
class SearchSource<T> {
  /// Database connection to read from.
  final Database database;

  /// Name of the table to search in.
  final String tableName;

  /// Columns to filter by using LIKE (OR condition).
  /// Most often `['name']`, but can also be `['name', 'ean']`.
  final List<String> searchColumns;

  /// Optional fixed WHERE condition (without parameters) appended
  /// to the search condition using AND.
  ///
  /// Example: `'is_used = 1'`
  final String? additionalWhere;

  /// Result ordering (SQL ORDER BY clause).
  ///
  /// Example: `'is_used DESC, name ASC'`
  final String orderBy;

  /// Maximum number of returned results. Null = unlimited.
  final int? limit;

  /// Function that transforms a single database row into an object of type [T].
  final T Function(Map<String, dynamic> row) fromRow;

  const SearchSource({
    required this.database,
    required this.tableName,
    required this.searchColumns,
    this.additionalWhere,
    this.orderBy = 'name ASC',
    this.limit,
    required this.fromRow,
  });
}

/// Generic search service capable of searching any number of
/// database sources and aggregating results into a single list.
///
/// ## Usage
///
/// ```dart
/// // 1. Create an instance once (or pass it via DI):
/// final searchService = SearchService();
///
/// // 2. Define sources:
/// final sources = [
///   SearchSource<FoodSearchResult>(
///     database: await FoodDatabase.instance.database,
///     tableName: 'Food',
///     searchColumns: ['name'],
///     additionalWhere: 'is_used = 1 OR is_used = 0', // all active
///     orderBy: 'is_used DESC, name ASC',
///     fromRow: (row) => FoodSearchResult(
///       id: row['id'] as int,
///       name: row['name'] as String,
///       source: FoodSource.catalog,
///       kcalPer100: (row['kcal_per_100'] as num).toDouble(),
///       proteinPer100: (row['protein_g'] as num).toDouble(),
///       carbsPer100: (row['carbs_g'] as num).toDouble(),
///       fatPer100: (row['fat_g'] as num).toDouble(),
///       unit: row['unit'] as String? ?? 'g',
///       ean: row['ean'] as String? ?? '',
///     ),
///   ),
/// ];
///
/// // 3. Run the search:
/// final results = await searchService.search<FoodSearchResult>('jablko', sources);
/// ```
class SearchService {
  /// Searches [query] across all given [sources] and returns an aggregated list
  /// of results of type [T].
  ///
  /// - If [query] is an empty string or whitespace, returns all records
  ///   (according to each source's [limit]).
  /// - Results are concatenated in the order of sources. If you want different ordering,
  ///   sort the resulting list yourself.
  Future<List<T>> search<T>(
    String query,
    List<SearchSource<T>> sources,
  ) async {
    final results = <T>[];
    final trimmed = query.trim();

    for (final source in sources) {
      final rows = await _querySource(trimmed, source);
      results.addAll(rows.map(source.fromRow));
    }

    return results;
  }

  /// Searches in a single specific source.
  Future<List<T>> searchSingle<T>(
    String query,
    SearchSource<T> source,
  ) async {
    final trimmed = query.trim();
    final rows = await _querySource(trimmed, source);
    return rows.map(source.fromRow).toList();
  }

  // ---------------------------------------------------------------------------
  // Internal methods
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _querySource<T>(
    String trimmedQuery,
    SearchSource<T> source,
  ) async {
    final whereParts = <String>[];
    final whereArgs = <dynamic>[];

    if (trimmedQuery.isNotEmpty) {
      // Build OR condition for each searchColumn
      final likeConditions = source.searchColumns
          .map((col) => '$col LIKE ?')
          .join(' OR ');
      whereParts.add('($likeConditions)');

      for (var _ in source.searchColumns) {
        whereArgs.add('%$trimmedQuery%');
      }
    }

    if (source.additionalWhere != null &&
        source.additionalWhere!.isNotEmpty) {
      whereParts.add('(${source.additionalWhere})');
    }

    final whereClause =
        whereParts.isNotEmpty ? whereParts.join(' AND ') : null;

    return await source.database.query(
      source.tableName,
      where: whereClause,
      whereArgs: whereArgs.isNotEmpty ? whereArgs : null,
      orderBy: source.orderBy,
      limit: source.limit,
    );
  }
}
