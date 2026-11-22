import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:calculate/service/food_sync_service.dart';

Future<void> main() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final dbFile = File('food.db');
  if (await dbFile.exists()) await dbFile.delete();

  final db = await openDatabase(
    dbFile.path,
    version: 1,
    onCreate: (db, version) async {
      await db.execute('CREATE TABLE Dbversion (version INTEGER PRIMARY KEY)');
      await db.execute('''
        CREATE TABLE Food (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
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
          is_custom INTEGER NOT NULL DEFAULT 0,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
    },
  );

  final syncService = FoodSyncService(db);

  print('1. PRAZDNA food.db vytvorena. Ukaz ji ve videu a stiskni ENTER...');
  stdin.readLineSync();

  await syncService.importFromSnapshot('test/fixtures/snapshot_1.db.gz');
  print('2. SNAPSHOT nacten (verze 1, 3 potraviny). Obnov pohled a stiskni ENTER...');
  stdin.readLineSync();

  await syncService.applyDelta('test/fixtures/delta_1_2.json');
  print('3. DELTA aplikovana (verze 2, 4 potraviny). Obnov pohled a stiskni ENTER...');
  stdin.readLineSync();

  await db.close();
}