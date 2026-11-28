import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:calculate/database/food_database.dart';
import 'package:calculate/database/user_database.dart';
import 'package:calculate/models/tables/food.dart';
import 'package:calculate/models/tables/custom_food.dart';
import 'package:calculate/models/in_memory/food_search_result.dart';
import 'package:calculate/models/tables/diary_entry.dart';
import 'package:calculate/services/search_service.dart';
import 'package:calculate/services/food_search_service.dart';
import 'package:calculate/services/diary_entry_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    // First close DB (release file handles), then delete files
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

  // ---------------------------------------------------------------------------
  // SearchService – unit tests (generic engine)
  // ---------------------------------------------------------------------------

  group('SearchService – generický engine', () {
    test('vrátí všechny záznamy při prázdném dotazu', () async {
      // Insert test foods
      await FoodDatabase.instance.insertFood(Food(
        id: 1,
        name: 'Jablko',
        kcalPer100: 52,
        proteinG: 0.3,
        carbsG: 14,
        sugarsG: 10,
        fatG: 0.2,
        saturatedFatG: 0,
        fibersG: 2.4,
        saltG: 0,
      ));
      await FoodDatabase.instance.insertFood(Food(
        id: 2,
        name: 'Banán',
        kcalPer100: 89,
        proteinG: 1.1,
        carbsG: 23,
        sugarsG: 12,
        fatG: 0.3,
        saturatedFatG: 0,
        fibersG: 2.6,
        saltG: 0,
      ));

      final db = await FoodDatabase.instance.database;
      final source = SearchSource<String>(
        database: db,
        tableName: 'Food',
        searchColumns: ['name'],
        orderBy: 'name ASC',
        fromRow: (row) => row['name'] as String,
      );

      final service = SearchService();
      final results = await service.searchSingle('', source);

      expect(results.length, 2);
      expect(results, containsAll(['Jablko', 'Banán']));
    });

    test('filtruje záznamy podle LIKE dotazu', () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 10,
        name: 'Ovesné vločky',
        kcalPer100: 370,
        proteinG: 13,
        carbsG: 60,
        sugarsG: 1,
        fatG: 7,
        saturatedFatG: 1.5,
        fibersG: 10,
        saltG: 0.01,
      ));
      await FoodDatabase.instance.insertFood(Food(
        id: 11,
        name: 'Ovesná kaše',
        kcalPer100: 68,
        proteinG: 2.4,
        carbsG: 12,
        sugarsG: 0.5,
        fatG: 1.2,
        saturatedFatG: 0.3,
        fibersG: 1.5,
        saltG: 0.1,
      ));
      await FoodDatabase.instance.insertFood(Food(
        id: 12,
        name: 'Rýže',
        kcalPer100: 130,
        proteinG: 2.7,
        carbsG: 28,
        sugarsG: 0.1,
        fatG: 0.3,
        saturatedFatG: 0.1,
        fibersG: 0.4,
        saltG: 0,
      ));

      final db = await FoodDatabase.instance.database;
      final source = SearchSource<String>(
        database: db,
        tableName: 'Food',
        searchColumns: ['name'],
        orderBy: 'name ASC',
        fromRow: (row) => row['name'] as String,
      );

      final service = SearchService();
      final results = await service.searchSingle('Oves', source);

      expect(results.length, 2);
      expect(results, containsAll(['Ovesné vločky', 'Ovesná kaše']));
      expect(results, isNot(contains('Rýže')));
    });

    test('prohledá více sloupců (name OR ean)', () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 20,
        ean: '8590000000012',
        name: 'Mléko 1.5%',
        kcalPer100: 46,
        proteinG: 3.3,
        carbsG: 4.8,
        sugarsG: 4.8,
        fatG: 1.5,
        saturatedFatG: 1.0,
        fibersG: 0,
        saltG: 0.1,
      ));

      final db = await FoodDatabase.instance.database;
      final source = SearchSource<Map<String, dynamic>>(
        database: db,
        tableName: 'Food',
        searchColumns: ['name', 'ean'],
        orderBy: 'name ASC',
        fromRow: (row) => Map<String, dynamic>.from(row),
      );

      final service = SearchService();

      // Search by EAN
      final byEan = await service.searchSingle('859000000001', source);
      expect(byEan.length, 1);
      expect(byEan.first['name'], 'Mléko 1.5%');

      // Search by name
      final byName = await service.searchSingle('Mléko', source);
      expect(byName.length, 1);
    });

    test('limit omezuje počet vrácených výsledků', () async {
      for (int i = 1; i <= 5; i++) {
        await FoodDatabase.instance.insertFood(Food(
          id: 100 + i,
          name: 'Testovací potravina $i',
          kcalPer100: 100,
          proteinG: 5,
          carbsG: 15,
          sugarsG: 2,
          fatG: 3,
          saturatedFatG: 1,
          fibersG: 1,
          saltG: 0,
        ));
      }

      final db = await FoodDatabase.instance.database;
      final source = SearchSource<String>(
        database: db,
        tableName: 'Food',
        searchColumns: ['name'],
        orderBy: 'name ASC',
        limit: 3,
        fromRow: (row) => row['name'] as String,
      );

      final service = SearchService();
      final results = await service.searchSingle('Testovací', source);
      expect(results.length, 3);
    });

    test('agreguje výsledky z více zdrojů', () async {
      // Source 1: food.db
      await FoodDatabase.instance.insertFood(Food(
        id: 200,
        name: 'Katalogová tyčinka',
        kcalPer100: 450,
        proteinG: 20,
        carbsG: 40,
        sugarsG: 10,
        fatG: 18,
        saturatedFatG: 5,
        fibersG: 3,
        saltG: 0.2,
      ));

      // Source 2: user.db
      await UserDatabase.instance.insertCustomFood(CustomFood(
        name: 'Vlastní tyčinka',
        kcalPer100: 410,
        proteinG: 18,
        carbsG: 45,
        fatG: 16,
      ));

      final foodDb = await FoodDatabase.instance.database;
      final userDb = await UserDatabase.instance.database;

      final sources = [
        SearchSource<String>(
          database: foodDb,
          tableName: 'Food',
          searchColumns: ['name'],
          orderBy: 'name ASC',
          fromRow: (row) => row['name'] as String,
        ),
        SearchSource<String>(
          database: userDb,
          tableName: 'CustomFood',
          searchColumns: ['name'],
          orderBy: 'name ASC',
          fromRow: (row) => row['name'] as String,
        ),
      ];

      final service = SearchService();
      final results = await service.search('tyčinka', sources);

      expect(results.length, 2);
      expect(results, containsAll(['Katalogová tyčinka', 'Vlastní tyčinka']));
    });
  });

  // ---------------------------------------------------------------------------
  // FoodSearchService – integration tests
  // ---------------------------------------------------------------------------

  group('FoodSearchService – integrační testy', () {
    late FoodSearchService foodSearch;

    setUp(() {
      foodSearch = FoodSearchService();
    });

    test('searchByName najde potraviny v obou databázích', () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 300,
        name: 'Jogurt bílý',
        kcalPer100: 61,
        proteinG: 5,
        carbsG: 7,
        sugarsG: 7,
        fatG: 1.5,
        saturatedFatG: 1,
        fibersG: 0,
        saltG: 0.1,
      ));
      await UserDatabase.instance.insertCustomFood(CustomFood(
        name: 'Jogurt domácí',
        kcalPer100: 55,
        proteinG: 4,
        carbsG: 6,
        fatG: 1,
      ));

      final results = await foodSearch.searchByName('Jogurt');
      expect(results.length, 2);

      final sources = results.map((r) => r.source).toSet();
      expect(sources, containsAll([FoodSource.catalog, FoodSource.custom]));
    });

    test('searchByName vrátí prázdný seznam, pokud nic neodpovídá', () async {
      final results = await foodSearch.searchByName('XYZ_neexistuje_12345');
      expect(results, isEmpty);
    });

    test('searchCatalogFoods prohledá pouze food.db', () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 400,
        name: 'Sýr eidam 30%',
        kcalPer100: 290,
        proteinG: 25,
        carbsG: 0.5,
        sugarsG: 0.5,
        fatG: 20,
        saturatedFatG: 13,
        fibersG: 0,
        saltG: 1.5,
      ));
      await UserDatabase.instance.insertCustomFood(CustomFood(
        name: 'Sýr domácí',
        kcalPer100: 320,
        proteinG: 22,
        carbsG: 1,
        fatG: 24,
      ));

      final results = await foodSearch.searchCatalogFoods('Sýr');
      expect(results.length, 1);
      expect(results.first.source, FoodSource.catalog);
      expect(results.first.name, 'Sýr eidam 30%');
    });

    test('searchCustomFoods prohledá pouze user.db', () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 500,
        name: 'Brambory',
        kcalPer100: 77,
        proteinG: 2,
        carbsG: 17,
        sugarsG: 0.8,
        fatG: 0.1,
        saturatedFatG: 0,
        fibersG: 2.2,
        saltG: 0,
      ));
      await UserDatabase.instance.insertCustomFood(CustomFood(
        name: 'Brambory pečené',
        kcalPer100: 93,
        proteinG: 2.5,
        carbsG: 21,
        fatG: 0.2,
      ));

      final results = await foodSearch.searchCustomFoods('Brambory');
      expect(results.length, 1);
      expect(results.first.source, FoodSource.custom);
      expect(results.first.name, 'Brambory pečené');
    });

    test('FoodSearchResult.nutritionFor přepočítá hodnoty správně', () {
      const food = FoodSearchResult(
        id: 1,
        name: 'Testovací potravina',
        source: FoodSource.catalog,
        kcalPer100: 200,
        proteinPer100: 10,
        carbsPer100: 30,
        fatPer100: 5,
      );

      final nutrition = food.nutritionFor(150);

      expect(nutrition['kcal'], closeTo(300.0, 0.001));
      expect(nutrition['protein_g'], closeTo(15.0, 0.001));
      expect(nutrition['carbs_g'], closeTo(45.0, 0.001));
      expect(nutrition['fat_g'], closeTo(7.5, 0.001));
    });

    test('searchByEan najde potravinu v food.db dle EAN', () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 600,
        ean: '8590000000099',
        name: 'Proteinová tyčinka',
        kcalPer100: 380,
        proteinG: 30,
        carbsG: 35,
        sugarsG: 8,
        fatG: 10,
        saturatedFatG: 3,
        fibersG: 5,
        saltG: 0.3,
      ));

      final results = await foodSearch.searchByEan('8590000000099');
      expect(results.length, 1);
      expect(results.first.name, 'Proteinová tyčinka');
      expect(results.first.source, FoodSource.catalog);
    });

    test('searchByEan vrátí prázdný seznam pro prázdný EAN', () async {
      final results = await foodSearch.searchByEan('');
      expect(results, isEmpty);
    });

    test('neaktivní (soft-deleted) potraviny se nezobrazí ve vyhledávání',
        () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 601,
        ean: '8590000000101',
        name: 'Neaktivní mléko',
        kcalPer100: 50,
        proteinG: 3,
        carbsG: 5,
        sugarsG: 5,
        fatG: 1.5,
        saturatedFatG: 1,
        fibersG: 0,
        saltG: 0.1,
        isUsed: true,
        isActive: false,
      ));

      expect(await foodSearch.searchByName('Neaktivní'), isEmpty);
      expect(await foodSearch.searchCatalogFoods('Neaktivní'), isEmpty);
      expect(await foodSearch.searchByEan('8590000000101'), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // DiaryEntryService – unit tests for validation and saving
  // ---------------------------------------------------------------------------

  group('DiaryEntryService – validace', () {
    late DiaryEntryService service;
    const testFood = FoodSearchResult(
      id: 1,
      name: 'Testovací potravina',
      source: FoodSource.catalog,
      kcalPer100: 200,
      proteinPer100: 10,
      carbsPer100: 30,
      fatPer100: 5,
    );

    setUp(() {
      service = DiaryEntryService();
    });

    test('validace projde při správných vstupech', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '150',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(result.isValid, isTrue);
      expect(result.entry, isNotNull);
    });

    test('vrátí chybu při nevybrané potravině', () {
      final result = service.validate(
        selectedFood: null,
        amountText: '150',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(result.errors, contains(DiaryEntryError.noFoodSelected));
    });

    test('vrátí chybu při nulovém množství', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '0',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(result.errors, contains(DiaryEntryError.invalidAmount));
    });

    test('vrátí chybu při záporném množství', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '-50',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(result.errors, contains(DiaryEntryError.invalidAmount));
    });

    test('vrátí chybu při množství menším než 0.1', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '0.05',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(result.errors, contains(DiaryEntryError.invalidAmount));

      final minResult = service.validate(
        selectedFood: testFood,
        amountText: '0.1',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(minResult.isValid, isTrue);
    });

    test('vrátí chybu při neplatném formátu množství', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: 'abc',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(result.errors, contains(DiaryEntryError.invalidAmountFormat));
    });

    test('přijme čárku jako desetinný oddělovač', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '150,5',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );
      expect(result.isValid, isTrue);
      expect(result.entry?.amount, closeTo(150.5, 0.001));
    });

    test('vrátí chybu při neplatném datu', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '100',
        mealType: DiaryEntry.breakfast,
        date: '27-11-2026', // invalid format
      );
      expect(result.errors, contains(DiaryEntryError.invalidDate));
    });

    test('vrátí chybu při neplatném typu jídla', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '100',
        mealType: 'Neplatný typ',
        date: '2026-11-27',
      );
      expect(result.errors, contains(DiaryEntryError.invalidMealType));
    });

    test('přepočítá nutriční hodnoty správně', () {
      final result = service.validate(
        selectedFood: testFood,
        amountText: '200',
        mealType: DiaryEntry.lunch,
        date: '2026-11-27',
      );
      expect(result.isValid, isTrue);
      expect(result.entry?.kcal, closeTo(400.0, 0.001)); // 200 * 2
      expect(result.entry?.proteinG, closeTo(20.0, 0.001));
      expect(result.entry?.carbsG, closeTo(60.0, 0.001));
      expect(result.entry?.fatG, closeTo(10.0, 0.001));
    });

    test('recalculate vrátí správné hodnoty', () {
      final nutrition = service.recalculate(
        selectedFood: testFood,
        amount: 100,
      );
      expect(nutrition, isNotNull);
      expect(nutrition!['kcal'], closeTo(200.0, 0.001));
    });

    test('recalculate vrátí null při nulovém množství', () {
      final nutrition = service.recalculate(
        selectedFood: testFood,
        amount: 0,
      );
      expect(nutrition, isNull);
    });
  });

  group('DiaryEntryService – uložení do DB', () {
    late DiaryEntryService service;

    setUp(() {
      service = DiaryEntryService();
    });

    test('saveEntry uloží katalogovou potravinu a označí ji jako is_used', () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 700,
        name: 'Kuřecí prsa',
        kcalPer100: 165,
        proteinG: 31,
        carbsG: 0,
        sugarsG: 0,
        fatG: 3.6,
        saturatedFatG: 1,
        fibersG: 0,
        saltG: 0.07,
      ));

      const food = FoodSearchResult(
        id: 700,
        name: 'Kuřecí prsa',
        source: FoodSource.catalog,
        kcalPer100: 165,
        proteinPer100: 31,
        carbsPer100: 0,
        sugarsPer100: 0.5,
        fatPer100: 3.6,
        saturatedFatPer100: 1.0,
        fibersPer100: 0.2,
        saltPer100: 0.07,
      );

      final result = await service.saveEntry(
        selectedFood: food,
        amountText: '200',
        mealType: DiaryEntry.lunch,
        date: '2026-11-27',
      );

      expect(result.isValid, isTrue);
      expect(result.entry?.id, isNotNull);
      expect(result.entry?.foodId, 700);
      expect(result.entry?.customFoodId, isNull);
      expect(result.entry?.kcal, closeTo(330.0, 0.001));
      expect(result.entry?.sugarsG, closeTo(1.0, 0.001));
      expect(result.entry?.saturatedFatG, closeTo(2.0, 0.001));
      expect(result.entry?.fibersG, closeTo(0.4, 0.001));
      expect(result.entry?.saltG, closeTo(0.14, 0.001));

      // Verify that is_used was set
      final food700 = await FoodDatabase.instance.getFoodById(700);
      expect(food700?.isUsed, isTrue);

      // Verify that the entry is in the diary
      final entries =
          await UserDatabase.instance.getDiaryEntriesByDate('2026-11-27');
      expect(entries.length, 1);
      expect(entries.first.foodName, 'Kuřecí prsa');
      expect(entries.first.sugarsG, closeTo(1.0, 0.001));
      expect(entries.first.saturatedFatG, closeTo(2.0, 0.001));
      expect(entries.first.fibersG, closeTo(0.4, 0.001));
      expect(entries.first.saltG, closeTo(0.14, 0.001));
    });

    test('saveEntry uloží vlastní potravinu (custom_food_id, food_id=0)', () async {
      await UserDatabase.instance.insertCustomFood(CustomFood(
        name: 'Domácí granola',
        kcalPer100: 450,
        proteinG: 12,
        carbsG: 55,
        fatG: 20,
      ));
      final customFoods =
          await UserDatabase.instance.searchCustomFoodsByName('granola');
      final customId = customFoods.first.id!;

      final food = FoodSearchResult(
        id: customId,
        name: 'Domácí granola',
        source: FoodSource.custom,
        kcalPer100: 450,
        proteinPer100: 12,
        carbsPer100: 55,
        fatPer100: 20,
      );

      final result = await service.saveEntry(
        selectedFood: food,
        amountText: '50',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );

      expect(result.isValid, isTrue);
      expect(result.entry?.foodId, 0);
      expect(result.entry?.customFoodId, customId);
      expect(result.entry?.kcal, closeTo(225.0, 0.001));
    });

    test('saveEntry selže při neplatných vstupech a nic neuloží', () async {
      final result = await service.saveEntry(
        selectedFood: null,
        amountText: '-10',
        mealType: DiaryEntry.breakfast,
        date: '2026-11-27',
      );

      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);

      final entries =
          await UserDatabase.instance.getDiaryEntriesByDate('2026-11-27');
      expect(entries, isEmpty);
    });

    test('saveEntry odmítne uložit neaktivní (soft-deleted) potravinu',
        () async {
      await FoodDatabase.instance.insertFood(Food(
        id: 701,
        name: 'Smazané jídlo',
        kcalPer100: 100,
        proteinG: 5,
        carbsG: 10,
        sugarsG: 2,
        fatG: 3,
        saturatedFatG: 1,
        fibersG: 1,
        saltG: 0.1,
        isUsed: true,
        isActive: false,
      ));

      const staleSearchResult = FoodSearchResult(
        id: 701,
        name: 'Smazané jídlo',
        source: FoodSource.catalog,
        kcalPer100: 100,
        proteinPer100: 5,
        carbsPer100: 10,
        fatPer100: 3,
      );

      final result = await service.saveEntry(
        selectedFood: staleSearchResult,
        amountText: '100',
        mealType: DiaryEntry.lunch,
        date: '2026-11-27',
      );

      expect(result.isValid, isFalse);
      expect(result.errors, contains(DiaryEntryError.foodInactive));
      expect(
        await UserDatabase.instance.getDiaryEntriesByDate('2026-11-27'),
        isEmpty,
      );
    });
  });
}
