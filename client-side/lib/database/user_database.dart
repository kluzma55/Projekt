import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/tables/custom_food.dart';
import '../models/tables/custom_meal.dart';
import '../models/tables/diary_entry.dart';
import '../models/tables/user_profile.dart';
import '../models/tables/activity.dart';
import '../models/tables/activity_log.dart';
import 'food_database.dart';
import '../models/tables/body_measurement.dart';
import '../models/tables/water_log.dart';

class UserDatabase {
  static final UserDatabase instance = UserDatabase._init();
  static Database? _database;

  UserDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('user.db');
    return _database!;
  }

  Future<Database> _initDB(String fileName) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, fileName);

    return await openDatabase(
      path,
      version: 2,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      final cols = await db.rawQuery('PRAGMA table_info(DiaryEntry)');
      final hasUnit = cols.any((c) => c['name'] == 'unit');
      if (hasUnit) {
        await db.transaction((txn) async {
          await txn.execute('''
            CREATE TABLE DiaryEntry_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              food_id INTEGER NOT NULL,
              custom_food_id INTEGER,
              meal_id INTEGER,
              food_name TEXT NOT NULL,
              amount REAL NOT NULL,
              kcal REAL NOT NULL,
              protein_g REAL NOT NULL,
              carbs_g REAL NOT NULL,
              fat_g REAL NOT NULL,
              is_fluid_intake INTEGER NOT NULL DEFAULT 0,
              meal_type TEXT NOT NULL,
              date TEXT NOT NULL
            )
          ''');
          await txn.execute('''
            INSERT INTO DiaryEntry_new (
              id, food_id, custom_food_id, meal_id, food_name, amount,
              kcal, protein_g, carbs_g, fat_g, is_fluid_intake, meal_type, date
            )
            SELECT
              id, food_id, custom_food_id, meal_id, food_name, amount,
              kcal, protein_g, carbs_g, fat_g, is_fluid_intake, meal_type, date
            FROM DiaryEntry
          ''');
          await txn.execute('DROP TABLE DiaryEntry');
          await txn.execute('ALTER TABLE DiaryEntry_new RENAME TO DiaryEntry');
          await txn.execute(
            'CREATE INDEX IF NOT EXISTS idx_diary_date ON DiaryEntry (date)',
          );
        });
      }
    }
  }
// insertion of basic activities into the Activity table (can be modified further)
  Future<void> _seedDefaultActivities(Database db) async {
    final defaultActivities = [
      {'name': 'Běh', 'kcal_per_hour_per_kg': 10.0, 'has_distance': 1},
      {'name': 'Běh na pásu', 'kcal_per_hour_per_kg': 9.5, 'has_distance': 1},
      {'name': 'Běh v terénu', 'kcal_per_hour_per_kg': 11.0, 'has_distance': 1},
      {'name': 'Chůze', 'kcal_per_hour_per_kg': 3.8, 'has_distance': 1},
      {'name': 'Jízda na kole', 'kcal_per_hour_per_kg': 7.5, 'has_distance': 1},
      {'name': 'Plavání', 'kcal_per_hour_per_kg': 7.0, 'has_distance': 1},
      {'name': 'Posilovna / silový trénink', 'kcal_per_hour_per_kg': 5.0, 'has_distance': 0},
      {'name': 'Jóga / protažení', 'kcal_per_hour_per_kg': 2.5, 'has_distance': 0},
    ];

    for (final item in defaultActivities) {
      await db.insert('Activity', item);
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE UserProfile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_user_id INTEGER,
        email TEXT,
        name TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        height_cm REAL NOT NULL,
        age INTEGER NOT NULL,
        gender TEXT NOT NULL,
        daily_kcal_goal REAL NOT NULL,
        daily_protein_goal REAL NOT NULL,
        daily_carbs_goal REAL NOT NULL,
        daily_fat_goal REAL NOT NULL,
        daily_water_goal_ml REAL NOT NULL
      )
    ''');

await db.execute('''
      CREATE TABLE CustomFood (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ean TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT 'g',
        kcal_per_100 REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        sugars_g REAL NOT NULL DEFAULT 0,
        fat_g REAL NOT NULL,
        saturated_fat_g REAL NOT NULL DEFAULT 0,
        fibers_g REAL NOT NULL DEFAULT 0,
        salt_g REAL NOT NULL DEFAULT 0
      )
    ''');

await db.execute('''
      CREATE TABLE CustomMeal (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        total_portions INTEGER NOT NULL DEFAULT 1
      )
    ''');

await db.execute('''
      CREATE TABLE CustomMealIngredient (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        meal_id INTEGER NOT NULL,
        food_id INTEGER,
        custom_food_id INTEGER,
        food_name TEXT NOT NULL,
        amount_grams REAL NOT NULL,
        kcal REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        fat_g REAL NOT NULL,
        FOREIGN KEY (meal_id) REFERENCES CustomMeal (id) ON DELETE CASCADE,
        FOREIGN KEY (custom_food_id) REFERENCES CustomFood (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE DiaryEntry (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        food_id INTEGER NOT NULL,
        custom_food_id INTEGER,
        meal_id INTEGER,
        food_name TEXT NOT NULL,
        amount REAL NOT NULL,
        kcal REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        fat_g REAL NOT NULL,
        is_fluid_intake INTEGER NOT NULL DEFAULT 0,
        meal_type TEXT NOT NULL,
        date TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_custom_food_name ON CustomFood (name)');
    await db.execute('CREATE INDEX idx_custom_food_ean ON CustomFood (ean)');
    await db.execute('CREATE INDEX idx_diary_date ON DiaryEntry (date)');
  
    await db.execute('''
      CREATE TABLE Activity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        kcal_per_hour_per_kg REAL NOT NULL,
        has_distance INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ActivityLog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        activity_id INTEGER,
        activity_name TEXT NOT NULL,
        duration_minutes INTEGER NOT NULL,
        distance_km REAL,
        burned_kcal REAL NOT NULL,
        date TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_activity_catalog_name ON Activity (name)');
    await db.execute('CREATE INDEX idx_activity_date ON ActivityLog (date)');

    await _seedDefaultActivities(db);

    await db.execute('''
      CREATE TABLE BodyMeasurement (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        weight_kg REAL NOT NULL,
        body_fat_percent REAL,
        muscle_mass_kg REAL
      )
    ''');

    await db.execute('CREATE INDEX idx_measurement_date ON BodyMeasurement (date)');
  
  await db.execute('''
      CREATE TABLE WaterLog (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount_ml REAL NOT NULL,
        date TEXT NOT NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_water_date ON WaterLog (date)');
  }
  // --- CRUD for CustomFood ---

Future<int> insertCustomFood(CustomFood food) async {
    final db = await database;
    return await db.insert('CustomFood', food.toMap());
  }

  Future<CustomFood?> getCustomFoodById(int id) async {
    final db = await database;
    final maps = await db.query('CustomFood', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return CustomFood.fromMap(maps.first);
  }

  Future<CustomFood?> getCustomFoodByEan(String ean) async {
    final db = await database;
    final maps = await db.query(
      'CustomFood',
      where: 'ean = ?',
      whereArgs: [ean],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return CustomFood.fromMap(maps.first);
  }

  Future<List<CustomFood>> getAllCustomFoods() async {
    final db = await database;
    final maps = await db.query('CustomFood', orderBy: 'name ASC');
    return maps.map((m) => CustomFood.fromMap(m)).toList();
  }

  Future<List<CustomFood>> searchCustomFoodsByName(String query) async {
    final db = await database;
    final maps = await db.query(
      'CustomFood',
      where: 'name LIKE ?',
      whereArgs: ['%$query%'],
      orderBy: 'name ASC',
    );
    return maps.map((m) => CustomFood.fromMap(m)).toList();
  }

  Future<int> updateCustomFood(CustomFood food) async {
    final db = await database;
    return await db.update(
      'CustomFood',
      food.toMap(),
      where: 'id = ?',
      whereArgs: [food.id],
    );
  }

  Future<int> deleteCustomFood(int id) async {
    final db = await database;
    return await db.delete('CustomFood', where: 'id = ?', whereArgs: [id]);
  }

  //CRUD for CustomMeal

  Future<int> insertCustomMeal(
      CustomMeal meal, List<CustomMealIngredient> ingredients) async {
    final db = await database;
    return await db.transaction((txn) async {
      final mealId = await txn.insert('CustomMeal', meal.toMap());
      for (final ing in ingredients) {
        final map = ing.toMap();
        map['meal_id'] = mealId;
        await txn.insert('CustomMealIngredient', map);
      }
      return mealId;
    });
  }

  Future<List<CustomMeal>> getAllCustomMeals() async {
    final db = await database;
    final maps = await db.query('CustomMeal', orderBy: 'name ASC');
    return maps.map((m) => CustomMeal.fromMap(m)).toList();
  }

  Future<List<CustomMealIngredient>> getMealIngredients(int mealId) async {
    final db = await database;
    final maps = await db.query('CustomMealIngredient',
        where: 'meal_id = ?', whereArgs: [mealId]);
    return maps.map((m) => CustomMealIngredient.fromMap(m)).toList();
  }

  Future<void> updateCustomMeal(
      CustomMeal meal, List<CustomMealIngredient> ingredients) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'CustomMeal',
        meal.toMap(),
        where: 'id = ?',
        whereArgs: [meal.id],
      );
      await txn.delete(
        'CustomMealIngredient',
        where: 'meal_id = ?',
        whereArgs: [meal.id],
      );
      for (final ing in ingredients) {
        final map = ing.toMap();
        map['meal_id'] = meal.id;
        await txn.insert('CustomMealIngredient', map);
      }
    });
  }

  Future<Map<String, double>> getPortionNutrition(int mealId) async {
    final db = await database;
    final mealMaps =
        await db.query('CustomMeal', where: 'id = ?', whereArgs: [mealId]);
    if (mealMaps.isEmpty) return {};

    final portions = (mealMaps.first['total_portions'] as int).clamp(1, 1000);
    final ingredients = await getMealIngredients(mealId);

    double totalKcal = 0, totalProtein = 0, totalCarbs = 0, totalFat = 0, totalWeight = 0;
    for (final ing in ingredients) {
      totalKcal += ing.kcal;
      totalProtein += ing.proteinG;
      totalCarbs += ing.carbsG;
      totalFat += ing.fatG;
      totalWeight += ing.amountGrams;
    }

    return {
      'amount_grams': totalWeight / portions,
      'kcal': totalKcal / portions,
      'protein_g': totalProtein / portions,
      'carbs_g': totalCarbs / portions,
      'fat_g': totalFat / portions,
    };
  }

  Future<int> deleteCustomMeal(int mealId) async {
    final db = await database;
    return await db.delete('CustomMeal', where: 'id = ?', whereArgs: [mealId]);
  }

  // --- CRUD for UserProfile ---

  Future<int> insertUserProfile(UserProfile profile) async {
    final db = await database;
    return await db.insert(
      'UserProfile',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserProfile?> getUserProfile() async {
    final db = await database;
    final maps = await db.query('UserProfile', limit: 1);
    if (maps.isEmpty) return null;
    return UserProfile.fromMap(maps.first);
  }

  Future<int> updateUserProfile(UserProfile profile) async {
    final db = await database;
    return await db.update(
      'UserProfile',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<int> deleteUserProfile(int id) async {
    final db = await database;
    return await db.delete(
      'UserProfile',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- CRUD for DiaryEntry ---

  Future<int> insertDiaryEntry(DiaryEntry entry) async {
    final db = await database;
    final id = await db.insert('DiaryEntry', entry.toMap());
    // Marks the food in food.db as used (only for foods from the catalog).
    // Best-effort: failure on food.db must not fail an already-saved diary entry.
    if (entry.customFoodId == null && entry.foodId > 0) {
      try {
        await FoodDatabase.instance.markFoodAsUsed(entry.foodId, isUsed: true);
      } catch (_) {}
    }
    return id;
  }

  Future<List<DiaryEntry>> getDiaryEntriesByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'DiaryEntry',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => DiaryEntry.fromMap(m)).toList();
  }

  Future<int> updateDiaryEntry(DiaryEntry entry) async {
    final db = await database;
    return await db.update(
      'DiaryEntry',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  Future<int> deleteDiaryEntry(int id) async {
    final db = await database;
    return await db.delete(
      'DiaryEntry',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // --- CRUD for Activity ---

/// Inserting a new activity into the catalog
  Future<int> insertActivity(Activity activity) async {
    final db = await database;
    return await db.insert(
      'Activity',
      activity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Loading all activities from the catalog (sorted alphabetically)
  Future<List<Activity>> getAllActivities() async {
    final db = await database;
    final maps = await db.query('Activity', orderBy: 'name ASC');
    return maps.map((m) => Activity.fromMap(m)).toList();
  }

  /// Searching the catalog by name (for the search field in UI)
  Future<List<Activity>> searchActivitiesByName(String query) async {
    final db = await database;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return await getAllActivities();
    }
    final maps = await db.query(
      'Activity',
      where: 'name LIKE ?',
      whereArgs: ['%$trimmed%'],
      orderBy: 'name ASC',
    );
    return maps.map((m) => Activity.fromMap(m)).toList();
  }

  /// Updating an activity in the catalog
  Future<int> updateActivity(Activity activity) async {
    final db = await database;
    return await db.update(
      'Activity',
      activity.toMap(),
      where: 'id = ?',
      whereArgs: [activity.id],
    );
  }

  /// Deleting an activity from the catalog
  Future<int> deleteActivity(int id) async {
    final db = await database;
    return await db.delete(
      'Activity',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD for ActivityLog (Logged activities in the user's diary)

  /// 1. Logging an activity selected "From list" (automatically calculates calories from profile)
  Future<int> logCatalogActivity({
    required Activity activity,
    required int durationMinutes,
    double? distanceKm,
    required String date,
  }) async {
    final profile = await getUserProfile();

    final burnedKcal = activity.calculateBurnedKcal(
      durationMinutes: durationMinutes,
      distanceKm: distanceKm,
      weightKg: profile?.weightKg ?? 70.0,
      heightCm: profile?.heightCm ?? 170.0,
      age: profile?.age ?? 25,
      gender: profile?.gender ?? 'F',
    );

    final log = ActivityLog(
      activityId: activity.id,
      activityName: activity.name,
      durationMinutes: durationMinutes,
      distanceKm: distanceKm,
      burnedKcal: burnedKcal,
      date: date,
    );

    return await insertActivityLog(log);
  }

  /// 2. Logging a "Custom activity" / from watch (or a ready ActivityLog object)
  Future<int> insertActivityLog(ActivityLog log) async {
    final db = await database;
    return await db.insert('ActivityLog', log.toMap());
  }

  /// Loading all logged activities for a specific day (YYYY-MM-DD)
  Future<List<ActivityLog>> getActivityLogsByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'ActivityLog',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => ActivityLog.fromMap(m)).toList();
  }

  /// Loading a single diary entry by ID (e.g. when opening for editing)
  Future<ActivityLog?> getActivityLogById(int id) async {
    final db = await database;
    final maps = await db.query(
      'ActivityLog',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return ActivityLog.fromMap(maps.first);
  }

  /// Sum of all burned calories for the given day (catalog + watch combined)
  Future<double> getTotalBurnedKcalByDate(String date) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(burned_kcal) AS total FROM ActivityLog WHERE date = ?',
      [date],
    );
    final total = result.first['total'];
    return total == null ? 0.0 : (total as num).toDouble();
  }

  /// Updating an already logged activity in the diary (e.g. changing time, distance, or kcal)
  Future<int> updateActivityLog(ActivityLog log) async {
    final db = await database;
    return await db.update(
      'ActivityLog',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  /// Deleting a logged activity from the diary
  Future<int> deleteActivityLog(int id) async {
    final db = await database;
    return await db.delete(
      'ActivityLog',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  //Crud for body measurement
  Future<int> insertBodyMeasurement(BodyMeasurement measurement) async {
    final db = await database;
    return await db.insert('BodyMeasurement', measurement.toMap());
  }

  Future<List<BodyMeasurement>> getAllBodyMeasurements() async {
    final db = await database;
    final maps = await db.query('BodyMeasurement', orderBy: 'date ASC');
    return maps.map((m) => BodyMeasurement.fromMap(m)).toList();
  }

  Future<BodyMeasurement?> getLatestBodyMeasurement() async {
    final db = await database;
    final maps = await db.query(
      'BodyMeasurement',
      orderBy: 'date DESC, id DESC',
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return BodyMeasurement.fromMap(maps.first);
  }

  Future<int> updateBodyMeasurement(BodyMeasurement measurement) async {
    final db = await database;
    return await db.update(
      'BodyMeasurement',
      measurement.toMap(),
      where: 'id = ?',
      whereArgs: [measurement.id],
    );
  }

  Future<int> deleteBodyMeasurement(int id) async {
    final db = await database;
    return await db.delete(
      'BodyMeasurement',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // CRUD for WaterLog

  Future<int> insertWaterLog(WaterLog log) async {
    final db = await database;
    return await db.insert('WaterLog', log.toMap());
  }

  Future<List<WaterLog>> getWaterLogsByDate(String date) async {
    final db = await database;
    final maps = await db.query(
      'WaterLog',
      where: 'date = ?',
      whereArgs: [date],
      orderBy: 'id ASC',
    );
    return maps.map((m) => WaterLog.fromMap(m)).toList();
  }

  Future<double> getTotalWaterMlByDate(String date) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount_ml) AS total FROM WaterLog WHERE date = ?',
      [date],
    );
    final total = result.first['total'];
    return total == null ? 0.0 : (total as num).toDouble();
  }

  Future<int> updateWaterLog(WaterLog log) async {
    final db = await database;
    return await db.update(
      'WaterLog',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
  }

  Future<int> deleteWaterLog(int id) async {
    final db = await database;
    return await db.delete(
      'WaterLog',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}