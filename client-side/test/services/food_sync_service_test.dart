import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// Uprav si název balíčku podle pubspec.yaml (např. package:calculate/services/food_sync_service.dart)
import 'package:calculate/service/food_sync_service.dart';

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
            is_custom INTEGER NOT NULL DEFAULT 0,
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

  test('Načtení snapshot_1.db.gz naplní 3 potraviny a nastaví verzi 1', () async {
    await syncService.importFromSnapshot(snapshotPath);

    final version = await syncService.getCurrentVersion();
    expect(version, 1);

    final foods = await db.query('Food', orderBy: 'id ASC');
    expect(foods.length, 3);

    expect(foods[0]['name'], 'Kuřecí prsa');
    expect(foods[1]['name'], 'Ovesné vločky');
    expect(foods[2]['name'], 'Plnotučné mléko');

    for (final food in foods) {
      expect(food['is_used'], 0);
      expect(food['is_custom'], 0);
      expect(food['is_active'], 1);
    }
  });

  test('Aplikace delta_1_2.json správně upraví, přidá i zneaktivní položky a nastaví verzi 2', () async {
    await syncService.importFromSnapshot(snapshotPath);
    await syncService.applyDelta(deltaPath);

    final version = await syncService.getCurrentVersion();
    expect(version, 2);

    final foods = await db.query('Food', orderBy: 'id ASC');
    expect(foods.length, 4);

    // ID 1: Kuřecí prsa -> aktualizováno 115 kcal a 25 g bílkovin
    final chicken = foods.firstWhere((f) => f['id'] == 1);
    expect(chicken['name'], 'Kuřecí prsa');
    expect(chicken['kcal_per_100'], 115.0);
    expect(chicken['protein_g'], 25.0);
    expect(chicken['is_active'], 1);

    // ID 3: Plnotučné mléko -> DELETED (pouze neaktivní, nesmazané)
    final milk = foods.firstWhere((f) => f['id'] == 3);
    expect(milk['name'], 'Plnotučné mléko');
    expect(milk['is_active'], 0);

    // ID 4: Banán -> CREATED
    final banana = foods.firstWhere((f) => f['id'] == 4);
    expect(banana['name'], 'Banán');
    expect(banana['kcal_per_100'], 89.0);
    expect(banana['protein_g'], 1.1);
    expect(banana['is_active'], 1);
  });

  test('Při chybě v delta JSONu se provede rollback a verze zůstane 1', () async {
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

      // Verze musí zůstat 1 a Plnotučné mléko musí být stále aktivní (is_active == 1)
      expect(await syncService.getCurrentVersion(), 1);
      final milk = (await db.query('Food', where: 'id = 3')).first;
      expect(milk['is_active'], 1);
    } finally {
      await tempDir.delete(recursive: true);
    }
  });
}