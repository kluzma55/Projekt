import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:calculate/service/food_sync_service.dart';

void main() {
  test(
    'Demo pro video',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;

      final dbPath = File('food.db').absolute.path;
      final dbFile = File(dbPath);
      if (await dbFile.exists()) await dbFile.delete();

      // KROK 1: Prázdná databáze
      var db = await openDatabase(
        dbPath,
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
      await db.close();
      print('>>> 1. PRAZDNA food.db pripravena (otevri ji v SQLite Vieweru)...');
      await Future.delayed(const Duration(seconds: 8));

      // KROK 2: Snapshot
      db = await openDatabase(dbPath);
      await FoodSyncService(db).importFromSnapshot('test/fixtures/snapshot_1.db.gz');
      await db.close();
      print('>>> 2. SNAPSHOT hotovy (zavri zalozku food.db a znovu ji otevri)...');
      await Future.delayed(const Duration(seconds: 8));

      // KROK 3: Delta
      db = await openDatabase(dbPath);
      await FoodSyncService(db).applyDelta('test/fixtures/delta_1_2.json');
      await db.close();
      print('>>> 3. DELTA hotova (zavri zalozku food.db a znovu ji otevri)...');
    },
  );
}