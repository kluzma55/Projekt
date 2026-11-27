import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class FoodSyncService {
  final Database db;

  FoodSyncService(this.db);

  /// Returns the current database version from the Dbversion table (0 if not set yet).
  Future<int> getCurrentVersion() async {
    final rows = await db.query('Dbversion', limit: 1);
    if (rows.isEmpty) return 0;
    return rows.first['version'] as int;
  }

  /// Unpacks a .db.gz snapshot into a temporary file, copies foods into food.db,
  /// and saves the database version (default 1) into the Dbversion table.
  Future<void> importFromSnapshot(
    String snapshotGzPath, {
    int snapshotVersion = 1,
  }) async {
    final gzFile = File(snapshotGzPath);
    if (!await gzFile.exists()) {
      throw FileSystemException('Snapshot soubor neexistuje', snapshotGzPath);
    }

    // 1. Unpack gzip into a temporary .db file
    final compressedBytes = await gzFile.readAsBytes();
    final decompressedBytes = gzip.decode(compressedBytes);

    final tempDir = await Directory.systemTemp.createTemp('food_snapshot_');
    final tempDbPath = p.join(tempDir.path, 'temp_snapshot.db');
    final tempDbFile = File(tempDbPath);
    await tempDbFile.writeAsBytes(decompressedBytes, flush: true);

    Database? snapshotDb;
    try {
      // 2. Open the unpacked snapshot as read-only
      snapshotDb = await openDatabase(tempDbPath, readOnly: true);

      // Detect table name in snapshot (handles 'Food', 'food', and 'foods')
      final tables = await snapshotDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND LOWER(name) LIKE 'food%'",
      );
      if (tables.isEmpty) {
        throw StateError('Ve snapshotu nebyla nalezena tabulka potravin.');
      }
      final sourceTable = tables.first['name'] as String;
      final snapshotRows = await snapshotDb.query(sourceTable);

      // 3. Copy data into local food.db in a single transaction
      await db.transaction((txn) async {
        // Clear any old catalog data before importing the snapshot
        await txn.delete('Food', where: 'is_custom = 0');

        for (final row in snapshotRows) {
          await txn.insert(
            'Food',
            {
              'id': row['id'],
              'ean': row['ean'] ?? '',
              'name': row['name'],
              'unit': row['unit'],
              'image_path': row['image_path'] ?? '',
              'kcal_per_100': (row['kcal_per_100'] as num).toDouble(),
              'protein_g': (row['protein_g'] as num).toDouble(),
              'carbs_g': (row['carbs_g'] as num).toDouble(),
              'sugars_g': (row['sugars_g'] as num).toDouble(),
              'fat_g': (row['fat_g'] as num).toDouble(),
              'saturated_fat_g': (row['saturated_fat_g'] as num).toDouble(),
              'fibers_g': (row['fibers_g'] as num).toDouble(),
              'salt_g': (row['salt_g'] as num).toDouble(),
              'is_used': 0,
              'is_custom': 0,
              'is_active': row['is_active'] ?? 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        // Set database version in Dbversion
        await txn.delete('Dbversion');
        await txn.insert('Dbversion', {'version': snapshotVersion});
      });
    } finally {
      await snapshotDb?.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }

  /// Applies changes from a delta JSON file in a single transaction.
  /// On error, rolls back and nothing changes in the database.
  Future<void> applyDelta(String deltaJsonPath) async {
    final jsonFile = File(deltaJsonPath);
    if (!await jsonFile.exists()) {
      throw FileSystemException('Delta JSON soubor neexistuje', deltaJsonPath);
    }

    final rawContent = await jsonFile.readAsString();
    final decoded = jsonDecode(rawContent);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Neplatný formát delta JSON souboru.');
    }

    final int fromVersion = decoded['from_version'] as int;
    final int toVersion = decoded['to_version'] as int;
    final List<dynamic> changes = decoded['changes'] as List<dynamic>;

    await db.transaction((txn) async {
      // Verify version continuity
      final versionRows = await txn.query('Dbversion', limit: 1);
      final currentVersion =
          versionRows.isEmpty ? 0 : versionRows.first['version'] as int;

      if (currentVersion != fromVersion) {
        throw StateError(
          'Neshoda verzí: lokální DB má verzi $currentVersion, ale delta vyžaduje $fromVersion.',
        );
      }

      for (final item in changes) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Položka v changes není validní objekt.');
        }

        final int foodId = item['food_id'] as int;
        final String action = item['action'] as String;

        switch (action) {
          case 'DELETED':
            // Soft delete – the food is not deleted, only marked as inactive
            final updatedCount = await txn.update(
              'Food',
              {'is_active': 0},
              where: 'id = ?',
              whereArgs: [foodId],
            );
            if (updatedCount == 0) {
              throw StateError('Potravina s id=$foodId pro DELETED neexistuje.');
            }
            break;

          case 'UPDATED':
            final rawData = item['data'];
            if (rawData is! Map<String, dynamic> || rawData.isEmpty) {
              throw FormatException(
                'Chybějící nebo prázdná data pro UPDATED u id=$foodId.',
              );
            }
            // Only fields listed in the data object are changed
            final updateFields = Map<String, dynamic>.from(rawData);
            updateFields.remove('id'); // Do not change primary key

            final updatedCount = await txn.update(
              'Food',
              updateFields,
              where: 'id = ?',
              whereArgs: [foodId],
            );
            if (updatedCount == 0) {
              throw StateError('Potravina s id=$foodId pro UPDATED neexistuje.');
            }
            break;

          case 'CREATED':
            final rawData = item['data'];
            if (rawData is! Map<String, dynamic>) {
              throw FormatException(
                'Chybějící data pro CREATED u id=$foodId.',
              );
            }
            await txn.insert(
              'Food',
              {
                'id': rawData['id'] ?? foodId,
                'ean': rawData['ean'] ?? '',
                'name': rawData['name'],
                'unit': rawData['unit'],
                'image_path': rawData['image_path'] ?? '',
                'kcal_per_100': (rawData['kcal_per_100'] as num).toDouble(),
                'protein_g': (rawData['protein_g'] as num).toDouble(),
                'carbs_g': (rawData['carbs_g'] as num).toDouble(),
                'sugars_g': (rawData['sugars_g'] as num).toDouble(),
                'fat_g': (rawData['fat_g'] as num).toDouble(),
                'saturated_fat_g':
                    (rawData['saturated_fat_g'] as num).toDouble(),
                'fibers_g': (rawData['fibers_g'] as num).toDouble(),
                'salt_g': (rawData['salt_g'] as num).toDouble(),
                'is_used': 0,
                'is_custom': 0,
                'is_active': 1,
              },
              conflictAlgorithm: ConflictAlgorithm.abort,
            );
            break;

          default:
            throw FormatException('Neznámá akce v delta souboru: $action');
        }
      }

      // After successfully applying all changes, save the new version number
      await txn.delete('Dbversion');
      await txn.insert('Dbversion', {'version': toVersion});
    });
  }
}