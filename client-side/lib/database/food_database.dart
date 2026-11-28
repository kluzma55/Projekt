import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/tables/db_version.dart';
import '../models/tables/food.dart';

class FoodDatabase {
  static final FoodDatabase instance = FoodDatabase._init();
  static Database? _database;

  FoodDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('food.db');
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
      final cols = await db.rawQuery('PRAGMA table_info(Food)');
      final hasIsActive = cols.any((c) => c['name'] == 'is_active');
      if (!hasIsActive) {
        await db.execute(
          'ALTER TABLE Food ADD COLUMN is_active INTEGER NOT NULL DEFAULT 1',
        );
      }
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE Dbversion (
        version INTEGER PRIMARY KEY,
        is_published INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE Food (
        id INTEGER PRIMARY KEY AuTOINCREMENT,
        ean TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL,
        unit TEXT NOT NULL DEFAULT 'g',
        image_path TEXT,
        kcal_per_100 REAL NOT NULL,
        protein_g REAL NOT NULL,
        carbs_g REAL NOT NULL,
        sugars_g REAL NOT NULL,
        fat_g REAL NOT NULL,
        saturated_fat_g REAL NOT NULL,
        fibers_g REAL NOT NULL,
        salt_g REAL NOT NULL,
        is_used INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        meal_type TEXT NOT NULL DEFAULT 'ostatní',
        updated_in_version_id INTEGER,
        FOREIGN KEY (updated_in_version_id) REFERENCES Dbversion (version)
      )
    ''');

    await db.execute('CREATE INDEX idx_food_ean ON Food (ean)');
    await db.execute('CREATE INDEX idx_food_name ON Food (name)');
  }

  // --- CRUD for Dbversion ---

Future<int> insertDbVersion(DbVersion dbVersion) async {
    final db = await database;
    return await db.insert('Dbversion', dbVersion.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<DbVersion?> getLatestDbVersion() async {
    final db = await database;
    final maps = await db.query('Dbversion', orderBy: 'version DESC', limit: 1);
    if (maps.isEmpty) return null;
    return DbVersion.fromMap(maps.first);
  }

  // --- CRUD for Food ---

  Future<int> insertFood(Food food) async {
    final db = await database;
    return await db.insert('Food', food.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Food?> getFoodById(int id) async {
    final db = await database;
    final maps = await db.query('Food', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Food.fromMap(maps.first);
  }

  Future<Food?> getFoodByEan(String ean) async {
    final db = await database;
    final maps = await db.query(
      'Food',
      where: 'ean = ? AND is_active = 1',
      whereArgs: [ean],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return Food.fromMap(maps.first);
  }

  Future<List<Food>> getAllFoods() async {
    final db = await database;
    final maps = await db.query(
      'Food',
      where: 'is_active = 1',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Food.fromMap(m)).toList();
  }

  Future<List<Food>> getUsedFoods() async {
    final db = await database;
    final maps = await db.query(
      'Food',
      where: 'is_used = 1',
      orderBy: 'name ASC',
    );
    return maps.map((m) => Food.fromMap(m)).toList();
  }

  Future<List<Food>> searchFoodsByName(String query) async {
    final db = await database;
    final maps = await db.query(
      'Food',
      where: 'name LIKE ? AND is_active = 1',
      whereArgs: ['%$query%'],
      orderBy: 'is_used DESC, name ASC',
    );
    return maps.map((m) => Food.fromMap(m)).toList();
  }

  Future<int> updateFood(Food food) async {
    final db = await database;
    return await db.update('Food', food.toMap(),
        where: 'id = ?', whereArgs: [food.id]);
  }

  Future<int> markFoodAsUsed(int foodId, {bool isUsed = true}) async {
    final db = await database;
    return await db.update('Food', {'is_used': isUsed ? 1 : 0},
        where: 'id = ?', whereArgs: [foodId]);
  }

  Future<int> deleteFood(int id) async {
    final db = await database;
    return await db.delete('Food', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }
}