import 'package:calculate/models/tables/diary_entry.dart';
import 'package:calculate/models/in_memory/food_search_result.dart';
import 'package:calculate/screens/homepage.dart';
import 'package:calculate/services/diary_entry_service.dart';
import 'package:calculate/services/food_search_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeFoodSearchService extends FoodSearchService {
  final List<FoodSearchResult> items;

  _FakeFoodSearchService(this.items);

  @override
  Future<List<FoodSearchResult>> searchByName(
    String query, {
    int? limit,
  }) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return items;
    return items
        .where((item) => item.name.toLowerCase().contains(trimmed))
        .toList();
  }
}

class _FakeDiaryEntryService extends DiaryEntryService {
  DiaryEntry? savedEntry;

  @override
  Future<DiaryEntryValidationResult> saveEntry({
    required FoodSearchResult? selectedFood,
    required String amountText,
    required String mealType,
    required String date,
    bool isFluidIntake = false,
  }) async {
    final validation = validate(
      selectedFood: selectedFood,
      amountText: amountText,
      mealType: mealType,
      date: date,
      isFluidIntake: isFluidIntake,
    );
    if (!validation.isValid) return validation;
    savedEntry = validation.entry!.copyWith(id: 1);
    return DiaryEntryValidationResult(entry: savedEntry, errors: const []);
  }
}

void main() {
  const sampleFoods = [
    FoodSearchResult(
      id: 1,
      name: 'Polotučné mléko',
      source: FoodSource.catalog,
      kcalPer100: 47,
      proteinPer100: 3.3,
      carbsPer100: 4.8,
      fatPer100: 1.5,
      unit: 'ml',
    ),
    FoodSearchResult(
      id: 2,
      name: 'Grilovaná kuřecí prsa',
      source: FoodSource.catalog,
      kcalPer100: 165,
      proteinPer100: 31.0,
      carbsPer100: 0.0,
      fatPer100: 3.6,
      unit: 'g',
    ),
    FoodSearchResult(
      id: 3,
      name: 'Kuřecí miska s quinoou',
      source: FoodSource.catalog,
      kcalPer100: 528,
      proteinPer100: 28.0,
      carbsPer100: 54.0,
      fatPer100: 20.0,
      unit: 'g',
    ),
    FoodSearchResult(
      id: 4,
      name: 'Kuřecí wrap s avokádem',
      source: FoodSource.catalog,
      kcalPer100: 485,
      proteinPer100: 24.0,
      carbsPer100: 42.0,
      fatPer100: 22.0,
      unit: 'g',
    ),
  ];

  testWidgets(
      'Homepage -> Search starts empty -> types query -> Detail -> Zpět flow',
      (tester) async {
    final fakeSearch = _FakeFoodSearchService(sampleFoods);
    final fakeDiary = _FakeDiaryEntryService();

    await tester.pumpWidget(
      MaterialApp(
        home: Homepage(
          foodSearchService: fakeSearch,
          diaryEntryService: fakeDiary,
        ),
      ),
    );

    // 1. Homepage renders "Přidat jídlo"
    expect(find.text('Přidat jídlo'), findsOneWidget);
    await tester.tap(find.text('Přidat jídlo'));
    await tester.pumpAndSettle();

    // 2. Search screen starts empty with dates hidden
    expect(find.text('Hledat jídlo'), findsOneWidget);
    expect(find.text('Zpět'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsNothing);
    expect(find.text('Grilovaná kuřecí prsa'), findsNothing);
    expect(find.text('Polotučné mléko'), findsNothing);

    // 3. Typing first letters populates results
    await tester.enterText(find.byType(TextField), 'kuřecí');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();

    expect(find.text('(3 výsledky)'), findsOneWidget);
    expect(find.text('Grilovaná kuřecí prsa'), findsOneWidget);
    expect(find.text('Polotučné mléko'), findsNothing);

    // 4. Tap item to open Detail jídla pre-filled with that food
    await tester.tap(find.text('Grilovaná kuřecí prsa'));
    await tester.pumpAndSettle();

    expect(find.text('Detail jídla'), findsOneWidget);
    expect(find.text('Grilovaná kuřecí prsa'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_month_outlined), findsOneWidget);

    // 5. Zpět on Detail goes directly back to Homepage
    await tester.tap(find.text('Zpět'));
    await tester.pumpAndSettle();
    expect(find.text('Přidat jídlo'), findsOneWidget);
  });

  testWidgets('Search screen supports scrolling through many results and saving',
      (tester) async {
    final manyFoods = List.generate(
      20,
      (i) => FoodSearchResult(
        id: i + 1,
        name: 'Potravina $i',
        source: FoodSource.catalog,
        kcalPer100: 100 + i.toDouble(),
        proteinPer100: 10,
        carbsPer100: 10,
        fatPer100: 2,
      ),
    );

    final fakeSearch = _FakeFoodSearchService(manyFoods);
    final fakeDiary = _FakeDiaryEntryService();

    await tester.pumpWidget(
      MaterialApp(
        home: Homepage(
          foodSearchService: fakeSearch,
          diaryEntryService: fakeDiary,
        ),
      ),
    );

    await tester.tap(find.text('Přidat jídlo'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Potravina');
    await tester.pump(const Duration(milliseconds: 160));
    await tester.pumpAndSettle();

    expect(find.text('(20 výsledků)'), findsOneWidget);

    // Scroll to the last item
    await tester.scrollUntilVisible(
      find.text('Potravina 19'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Potravina 19'), findsOneWidget);

    // Tap it -> Detail -> Zapsat do deníku -> returns to Homepage
    await tester.tap(find.text('Potravina 19'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Zapsat do deníku'));
    await tester.pumpAndSettle();

    expect(fakeDiary.savedEntry, isNotNull);
    expect(fakeDiary.savedEntry!.foodName, 'Potravina 19');
    expect(find.text('Přidat jídlo'), findsOneWidget);
    expect(find.text('Zapsáno do deníku'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });
}
