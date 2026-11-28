import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:calculate/services/food_sync_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late FoodSyncService syncService;

  const snapshotPath = 'test/fixtures/snapshot_1.db.gz';
  const deltaPath = 'test/fixtures/delta_1_2.json';

  setUp(() async {
    db = await openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE Food (
            id INTEGER PRIMARY KEY,
            ean TEXT NOT NULL,
            name TEXT NOT NULL,
            unit TEXT NOT NULL,
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
            is_active INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.execute('''
          CREATE TABLE Dbversion (
            version INTEGER NOT NULL
          )
        ''');
      },
    );
    syncService = FoodSyncService(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Načtení snapshot_1.db.gz naplní všechny 3 potraviny a nastaví verzi 1',
      () async {
    await syncService.importFromSnapshot(snapshotPath);

    final version = await syncService.getCurrentVersion();
    expect(version, 1);

    final foods = await db.query('Food', orderBy: 'id ASC');
    expect(foods.length, 3);

    expect(foods[0]['name'], 'Kuřecí prsa');
    expect(foods[0]['ean'], '8591234567890');
    expect(foods[0]['unit'], 'g');
    expect(
      foods[0]['image_path'],
      'https://cdn.yourproject.com/images/foods/kureci_prsa.jpg',
    );
    expect(foods[0]['kcal_per_100'], 110.0);
    expect(foods[1]['name'], 'Ovesné vločky');
    expect(foods[2]['name'], 'Plnotučné mléko');

    for (final food in foods) {
      expect(food['is_used'], 0);
      expect(food['is_active'], 1);
    }
  });

  test(
      'Delta DELETED pro nepoužitou potravinu (is_used=0) provede hard delete a nastaví verzi 2',
      () async {
    await syncService.importFromSnapshot(snapshotPath);
    await syncService.applyDelta(deltaPath);

    final version = await syncService.getCurrentVersion();
    expect(version, 2);

    final foods = await db.query('Food', orderBy: 'id ASC');
    expect(foods.length, 3);

    // ID 1: Chicken breast -> updated 115 kcal and 25 g protein
    final chicken = foods.firstWhere((f) => f['id'] == 1);
    expect(chicken['name'], 'Kuřecí prsa');
    expect(chicken['kcal_per_100'], 115.0);
    expect(chicken['protein_g'], 25.0);
    expect(chicken['is_active'], 1);

    // ID 3: Whole milk had is_used=0 -> hard deleted
    expect(foods.where((f) => f['id'] == 3), isEmpty);

    // ID 4: Banana -> CREATED
    final banana = foods.firstWhere((f) => f['id'] == 4);
    expect(banana['name'], 'Banán');
    expect(banana['ean'], '8593333333333');
    expect(banana['kcal_per_100'], 89.0);
    expect(banana['protein_g'], 1.1);
    expect(banana['is_active'], 1);
  });

  test(
      'Delta DELETED pro použitou potravinu (is_used=1) provede soft delete (is_active=0)',
      () async {
    await syncService.importFromSnapshot(snapshotPath);
    // Mark ID 3 as used locally
    await db.update('Food', {'is_used': 1}, where: 'id = 3');

    await syncService.applyDelta(deltaPath);

    expect(await syncService.getCurrentVersion(), 2);

    final foods = await db.query('Food', orderBy: 'id ASC');
    expect(foods.length, 4);

    final milk = foods.firstWhere((f) => f['id'] == 3);
    expect(milk['name'], 'Plnotučné mléko');
    expect(milk['is_used'], 1);
    expect(milk['is_active'], 0);
  });

  test('Při chybě v delta JSONu se provede rollback a verze zůstane 1',
      () async {
    await syncService.importFromSnapshot(snapshotPath);

    final tempDir = await Directory.systemTemp.createTemp('delta_err_');
    final badDeltaFile = File(p.join(tempDir.path, 'bad_delta.json'));
    await badDeltaFile.writeAsString('''
    {
      "from_version": 1,
      "to_version": 2,
      "changes": [
        {"food_id": 3, "action": "DELETED"},
        {"food_id": 999, "action": "NEEXISTUJICI_AKCE"}
      ]
    }
    ''');

    try {
      await expectLater(
        () => syncService.applyDelta(badDeltaFile.path),
        throwsFormatException,
      );

      // Version must remain 1 and Whole milk must still exist and be active
      expect(await syncService.getCurrentVersion(), 1);
      final milk = (await db.query('Food', where: 'id = 3')).first;
      expect(milk['is_active'], 1);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });

  test(
      'Opakovaný import snapshotu zachová is_used=1, aktualizuje existující a zneaktivní chybějící použité potraviny',
      () async {
    // Seed local DB before snapshot:
    // - id 1 (Kuřecí prsa): is_used=1, old kcal=99 -> exists in snapshot (110 kcal) -> updated, keeps is_used=1
    // - id 99 (Staré použité jídlo): is_used=1 -> missing from snapshot -> soft-deleted (is_active=0)
    // - id 100 (Staré nepoužité jídlo): is_used=0 -> missing from snapshot -> hard-deleted
    await db.insert('Food', {
      'id': 1,
      'ean': '8591234567890',
      'name': 'Kuřecí prsa (stará)',
      'unit': 'g',
      'image_path': '',
      'kcal_per_100': 99.0,
      'protein_g': 20.0,
      'carbs_g': 0.0,
      'sugars_g': 0.0,
      'fat_g': 1.0,
      'saturated_fat_g': 0.2,
      'fibers_g': 0.0,
      'salt_g': 0.1,
      'is_used': 1,
      'is_active': 1,
    });
    await db.insert('Food', {
      'id': 99,
      'ean': '',
      'name': 'Staré použité jídlo',
      'unit': 'g',
      'image_path': '',
      'kcal_per_100': 200.0,
      'protein_g': 10.0,
      'carbs_g': 20.0,
      'sugars_g': 5.0,
      'fat_g': 8.0,
      'saturated_fat_g': 2.0,
      'fibers_g': 1.0,
      'salt_g': 0.5,
      'is_used': 1,
      'is_active': 1,
    });
    await db.insert('Food', {
      'id': 100,
      'ean': '',
      'name': 'Staré nepoužité jídlo',
      'unit': 'g',
      'image_path': '',
      'kcal_per_100': 150.0,
      'protein_g': 5.0,
      'carbs_g': 15.0,
      'sugars_g': 2.0,
      'fat_g': 4.0,
      'saturated_fat_g': 1.0,
      'fibers_g': 1.0,
      'salt_g': 0.2,
      'is_used': 0,
      'is_active': 1,
    });

    await syncService.importFromSnapshot(snapshotPath);

    final foods = await db.query('Food', orderBy: 'id ASC');
    // Should contain 1, 2, 3 from snapshot + archived 99 (100 hard-deleted)
    expect(foods.length, 4);
    expect(foods.where((f) => f['id'] == 100), isEmpty);

    final chicken = foods.firstWhere((f) => f['id'] == 1);
    expect(chicken['name'], 'Kuřecí prsa');
    expect(chicken['kcal_per_100'], 110.0);
    expect(chicken['is_used'], 1);
    expect(chicken['is_active'], 1);

    final archived = foods.firstWhere((f) => f['id'] == 99);
    expect(archived['is_used'], 1);
    expect(archived['is_active'], 0);

    final oats = foods.firstWhere((f) => f['id'] == 2);
    expect(oats['is_used'], 0);
    expect(oats['is_active'], 1);
  });
}
