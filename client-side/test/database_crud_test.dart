import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:calculate/database/food_database.dart';
import 'package:calculate/database/user_database.dart';
import 'package:calculate/models/tables/db_version.dart';
import 'package:calculate/models/tables/diary_entry.dart';
import 'package:calculate/models/tables/food.dart';
import 'package:calculate/models/tables/user_profile.dart';
import 'package:calculate/models/tables/activity.dart';
import 'package:calculate/models/tables/activity_log.dart';
import 'package:calculate/models/tables/custom_meal.dart';
import 'package:calculate/models/tables/custom_food.dart';
import 'package:calculate/models/tables/body_measurement.dart';
import 'package:calculate/models/tables/water_log.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    // First close existing connections (release file handles), then delete files
    await FoodDatabase.instance.close();
    await UserDatabase.instance.close();
    final dbPath = await getDatabasesPath();
    final foodFile = File(p.join(dbPath, 'food.db'));
    final userFile = File(p.join(dbPath, 'user.db'));
    if (await foodFile.exists()) await foodFile.delete();
    if (await userFile.exists()) await userFile.delete();
  });

  tearDown(() async {
    await FoodDatabase.instance.close();
    await UserDatabase.instance.close();
  });

  test('CRUD operace pro food.db (Dbversion a Food včetně is_used)', () async {
    final foodDb = FoodDatabase.instance;

    //Version of the downloaded database
    await foodDb.insertDbVersion(
      DbVersion(version: 1),
    );

    //Insertion of food from the server catalog
    final apple = Food(
      id: 101,
      ean: '8590000000012',
      name: 'Jablko Golden',
      kcalPer100: 52.0,
      proteinG: 0.3,
      carbsG: 13.8,
      sugarsG: 10.4,
      fatG: 0.2,
      saturatedFatG: 0.0,
      fibersG: 2.4,
      saltG: 0.0,
      isUsed: false,
    );
    await foodDb.insertFood(apple);

    // READ verification of inserted data
    final latestVersion = await foodDb.getLatestDbVersion();
    expect(latestVersion?.version, 1);

    final loadedFood = await foodDb.getFoodById(101);
    expect(loadedFood?.name, 'Jablko Golden');
    expect(loadedFood?.isUsed, false);

    // UPDATE (marking is_used = true and changing name)
    await foodDb.markFoodAsUsed(101, isUsed: true);
    final usedFoods = await foodDb.getUsedFoods();
    expect(usedFoods.length, 1);
    expect(usedFoods.first.isUsed, true);

    await foodDb.updateFood(loadedFood!.copyWith(name: 'Jablko Gala', isUsed: true));
    expect((await foodDb.getFoodById(101))?.name, 'Jablko Gala');

    //DELETE
    await foodDb.deleteFood(101);
    expect(await foodDb.getFoodById(101), isNull);
  });

  test('CRUD operace pro user.db (UserProfile a DiaryEntry)', () async {
    final userDb = UserDatabase.instance;
    final foodDb = FoodDatabase.instance;

    // Preparing food in food.db to verify automatic setting of is_used
    await foodDb.insertFood(
      Food(
        id: 202,
        name: 'Ovesné vločky',
        kcalPer100: 370,
        proteinG: 13.0,
        carbsG: 60.0,
        sugarsG: 1.0,
        fatG: 7.0,
        saturatedFatG: 1.5,
        fibersG: 10.0,
        saltG: 0.01,
        isUsed: false,
      ),
    );

//Test for custom food
    final customFoodId = await userDb.insertCustomFood(
      CustomFood(
        name: 'Domácí ovesná tyčinka',
        kcalPer100: 410,
        proteinG: 18,
        carbsG: 45,
        fatG: 16,
      ),
    );
    final customFoods = await userDb.searchCustomFoodsByName('tyčinka');
    expect(customFoods.length, 1);

// Test for custom meal
final mealId = await userDb.insertCustomMeal(
      CustomMeal(name: 'Svačinový box', totalPortions: 2),
      [
        CustomMealIngredient(
          mealId: 0,
          foodId: 202,
          foodName: 'Ovesné vločky',
          amountGrams: 100,
          kcal: 370,
          proteinG: 13,
          carbsG: 60,
          fatG: 7,
        ),
        CustomMealIngredient(
          mealId: 0,
          customFoodId: customFoodId,
          foodName: 'Domácí ovesná tyčinka',
          amountGrams: 100,
          kcal: 410,
          proteinG: 18,
          carbsG: 45,
          fatG: 16,
        ),
      ],
    );

    final portion = await userDb.getPortionNutrition(mealId);
    expect(portion['kcal'], 390.0);

//CRUD tests for User Profile

    // CREATE user profile
    final profileId = await userDb.insertUserProfile(
      UserProfile(
        name: 'Market',
        weightKg: 62.0,
        heightCm: 170.0,
        age: 22,
        gender: 'F',
        dailyKcalGoal: 2000,
        dailyProteinGoal: 120,
        dailyCarbsGoal: 230,
        dailyFatGoal: 65,
        dailyWaterGoalMl: 2000.0,
      ),
    );

    // READ & UPDATE 
    var profile = await userDb.getUserProfile();
    expect(profile?.name, 'Market');

    await userDb.updateUserProfile(
      UserProfile(
        id: profileId,
        name: 'Market',
        weightKg: 61.5,
        heightCm: 170.0,
        age: 22,
        gender: 'F',
        dailyKcalGoal: 2100,
        dailyProteinGoal: 125,
        dailyCarbsGoal: 240,
        dailyFatGoal: 65.0,
        dailyWaterGoalMl: 2500.0,
      ),
    );
    profile = await userDb.getUserProfile();
    expect(profile?.dailyKcalGoal, 2100);
    expect(profile?.dailyWaterGoalMl, 2500.0);

// Activity Tests
final runningActivities = await userDb.searchActivitiesByName('Běh');
    expect(runningActivities.length, greaterThanOrEqualTo(3));

final customCatalogId = await userDb.insertActivity(
      Activity(
        name: 'Bruslení in-line',
        kcalPerHourPerKg: 7.0,
        hasDistance: true,
      ),
    );
    expect(customCatalogId, greaterThan(0));

expect(Activity.formatAveragePace(30, 5.0), '6:00 min/km');
    expect(Activity.formatAveragePace(30, null), '--:-- min/km');

final selectedRun = runningActivities.first;
    final catalogLogId = await userDb.logCatalogActivity(
      activity: selectedRun,
      durationMinutes: 30,
      distanceKm: 5.0,
      date: '2026-11-15',
    );
    expect(catalogLogId, greaterThan(0));

final watchLogId = await userDb.insertActivityLog(
      ActivityLog(
        activityId: null, // null = custom activity outside catalog
        activityName: 'Silový trénink (hodinky)',
        durationMinutes: 50,
        burnedKcal: 340.0,
        date: '2026-11-15',
      ),
    );
    expect(watchLogId, greaterThan(0));

final foundActivities = await userDb.searchActivitiesByName('Běh');
    expect(foundActivities, isNotEmpty);

    await userDb.logCatalogActivity(
      activity: foundActivities.first,
      durationMinutes: 30,
      distanceKm: 5.0,
      date: '2026-11-15',
    );

    await userDb.insertActivityLog(
      ActivityLog(
        activityId: null,
        activityName: 'Trénink (hodinky)',
        durationMinutes: 45,
        burnedKcal: 380.0,
        date: '2026-11-15',
      ),
    );

    final activityLogs = await userDb.getActivityLogsByDate('2026-11-15');
    expect(activityLogs.length, 4);

    final totalBurned = await userDb.getTotalBurnedKcalByDate('2026-11-15');
    expect(totalBurned, greaterThan(380.0));

// Body measurements
await userDb.insertBodyMeasurement(
      BodyMeasurement(date: '2026-11-15', weightKg: 61.8),
    );
    final weights = await userDb.getAllBodyMeasurements();
    expect(weights.length, 1);
    expect(weights.first.weightKg, 61.8);

// Tests for DiaryEntry
    // CREATE DiaryEntry -> should set isUsed = true for food 202
    final entryId = await userDb.insertDiaryEntry(
      DiaryEntry(
        foodId: 202,
        foodName: 'Ovesné vločky',
        amount: 80,
        kcal: 296,
        proteinG: 10.4,
        carbsG: 48.0,
        fatG: 5.6,
        date: '2026-11-12',
      ),
    );

    final updatedFood = await foodDb.getFoodById(202);
    expect(updatedFood?.isUsed, true);

    // READ, UPDATE & DELETE DiaryEntry
    var entries = await userDb.getDiaryEntriesByDate('2026-11-12');
    expect(entries.length, 1);
    expect(entries.first.amount, 80);

    await userDb.updateDiaryEntry(
      DiaryEntry(
        id: entryId,
        foodId: 202,
        foodName: 'Ovesné vločky',
        amount: 100,
        kcal: 370,
        proteinG: 13.0,
        carbsG: 60.0,
        fatG: 7.0,
        date: '2026-11-12',
      ),
    );
    entries = await userDb.getDiaryEntriesByDate('2026-11-12');
    expect(entries.first.amount, 100);

    await userDb.deleteDiaryEntry(entryId);
    expect(await userDb.getDiaryEntriesByDate('2026-11-12'), isEmpty);
  
    await UserDatabase.instance.insertWaterLog(
    WaterLog(amountMl: 250.0, date: '2026-11-15'),
  );

  });
}