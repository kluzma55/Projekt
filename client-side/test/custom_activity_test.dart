import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:calculate/database/user_database.dart';
import 'package:calculate/models/activity_log.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final db = UserDatabase.instance;
  late Directory testDirectory;

  const date = '2026-11-27';

  setUp(() async {
    await db.close();
    testDirectory = await Directory.systemTemp.createTemp('activity_test_');
    await databaseFactory.setDatabasesPath(testDirectory.path);
  });

  tearDown(() async {
    await db.close();
    await testDirectory.delete(recursive: true);
  });

  test('Uložení vlastní aktivity bez vzdálenosti', () async {
    final id = await db.insertActivityLog(
      ActivityLog(
        activityId: null,
        activityName: 'Chůze',
        durationMinutes: 30,
        burnedKcal: 150.0,
        date: date,
      ),
    );

    final activity = await db.getActivityLogById(id);

    expect(activity, isNotNull);
    expect(activity!.activityName, 'Chůze');
    expect(activity.durationMinutes, 30);
    expect(activity.burnedKcal, 150.0);
    expect(activity.distanceKm, isNull);
    expect(activity.activityId, isNull);
  });

  test('Uložení vlastní aktivity se vzdáleností', () async {
    final id = await db.insertActivityLog(
      ActivityLog(
        activityId: null,
        activityName: 'Běh',
        durationMinutes: 45,
        distanceKm: 5.0,
        burnedKcal: 300.0,
        date: date,
      ),
    );

    final activity = await db.getActivityLogById(id);

    expect(activity, isNotNull);
    expect(activity!.activityName, 'Běh');
    expect(activity.durationMinutes, 45);
    expect(activity.distanceKm, 5.0);
    expect(activity.burnedKcal, 300.0);
  });

  test('Správný součet denního výdeje', () async {
    await db.insertActivityLog(
      ActivityLog(
        activityName: 'Chůze',
        durationMinutes: 30,
        burnedKcal: 150.0,
        date: date,
      ),
    );

    await db.insertActivityLog(
      ActivityLog(
        activityName: 'Běh',
        durationMinutes: 45,
        burnedKcal: 300.0,
        date: date,
      ),
    );

    final activities = await db.getActivityLogsByDate(date);
    final total = await db.getTotalBurnedKcalByDate(date);

    expect(activities.length, 2);
    expect(total, 450.0);
  });

  test('Aktivity jsou oddělené podle data', () async {
    await db.insertActivityLog(
      ActivityLog(
        activityName: 'Chůze',
        durationMinutes: 30,
        burnedKcal: 150.0,
        date: date,
      ),
    );

    expect(await db.getActivityLogsByDate('2026-11-28'), isEmpty);
    expect(await db.getTotalBurnedKcalByDate('2026-11-28'), 0.0);
  });

  test('Trvalé uložení po uzavření databáze', () async {
    await db.insertActivityLog(
      ActivityLog(
        activityName: 'Chůze',
        durationMinutes: 30,
        burnedKcal: 150.0,
        date: date,
      ),
    );

    await db.close();

    final activities = await db.getActivityLogsByDate(date);

    expect(activities.length, 1);
    expect(activities.first.activityName, 'Chůze');
    expect(activities.first.burnedKcal, 150.0);
  });
}
