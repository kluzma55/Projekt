import 'package:calculate/models/tables/diary_entry.dart';
import 'package:calculate/models/in_memory/food_search_result.dart';
import 'package:calculate/screens/detail_jidla_screen.dart';
import 'package:calculate/services/diary_entry_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDiaryEntryService extends DiaryEntryService {
  DiaryEntry? savedEntry;
  List<DiaryEntryError> nextErrors = const [];

  @override
  Future<DiaryEntryValidationResult> saveEntry({
    required FoodSearchResult? selectedFood,
    required String amountText,
    required String mealType,
    required String date,
    bool isFluidIntake = false,
  }) async {
    if (nextErrors.isNotEmpty) {
      return DiaryEntryValidationResult(errors: nextErrors);
    }
    final validation = validate(
      selectedFood: selectedFood,
      amountText: amountText,
      mealType: mealType,
      date: date,
      isFluidIntake: isFluidIntake,
    );
    if (!validation.isValid) return validation;
    savedEntry = validation.entry!.copyWith(id: 42);
    return DiaryEntryValidationResult(entry: savedEntry, errors: const []);
  }
}

void main() {
  const milk = FoodSearchResult(
    id: 1,
    name: 'Polotučné mléko',
    source: FoodSource.catalog,
    kcalPer100: 47,
    proteinPer100: 3.3,
    carbsPer100: 4.8,
    fatPer100: 1.5,
    sugarsPer100: 4.8,
    saturatedFatPer100: 1.0,
    fibersPer100: 0.0,
    saltPer100: 0.1,
    unit: 'ml',
  );

  const chicken = FoodSearchResult(
    id: 2,
    name: 'Kuřecí prsa',
    source: FoodSource.catalog,
    kcalPer100: 165,
    proteinPer100: 31,
    carbsPer100: 0,
    fatPer100: 3.6,
    unit: 'g',
  );

  testWidgets('DetailJidlaScreen renders Figma elements and recalculates live',
      (tester) async {
    final fakeService = _FakeDiaryEntryService();
    final testDate = DateTime(2026, 11, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: DetailJidlaScreen(
          food: milk,
          selectedDate: testDate,
          createdAt: testDate,
          initialAmount: 250,
          initialMealType: DiaryEntry.morningSnack,
          diaryEntryService: fakeService,
        ),
      ),
    );

    expect(find.text('Detail jídla'), findsOneWidget);
    expect(find.text('Zpět'), findsOneWidget);
    expect(find.text('1. lis 2026'), findsOneWidget);
    expect(find.text('Polotučné mléko'), findsOneWidget);
    expect(find.text('ml'), findsOneWidget);
    expect(find.text('Jednotka'), findsNothing);
    expect(find.text('Započítat do tekutin'), findsOneWidget);
    expect(find.text('Zobrazit podrobnosti'), findsOneWidget);
    expect(find.text('Zapsat do deníku'), findsOneWidget);

    // 47 * 2.5 = 117.5 -> rounded to 118 kcal
    expect(find.text('118'), findsOneWidget);

    // Update amount to 100
    await tester.enterText(find.byType(TextField), '100');
    await tester.pump();
    expect(find.text('47'), findsOneWidget);

    // Rejects invalid characters and only allows digits + single dot
    await tester.enterText(find.byType(TextField), '12.5abc');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '100');

    await tester.enterText(find.byType(TextField), '12.5');
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '12.5');

    // Expand nutrition details
    await tester.ensureVisible(find.text('Zobrazit podrobnosti'));
    await tester.tap(find.text('Zobrazit podrobnosti'));
    await tester.pump();
    expect(find.text('Skrýt podrobnosti'), findsOneWidget);
    expect(find.text('z toho cukry'), findsOneWidget);
    expect(find.text('z toho nasycené mastné kyseliny'), findsOneWidget);
    expect(find.text('Vláknina'), findsOneWidget);
    expect(find.text('Sůl'), findsOneWidget);

    // Open meal type bottom sheet and pick Večeře
    await tester.ensureVisible(find.text('Dopolední svačina'));
    await tester.tap(find.text('Dopolední svačina'));
    await tester.pumpAndSettle();
    expect(find.text('Zařadit do jídla'), findsOneWidget);
    await tester.tap(find.text('Večeře'));
    await tester.pumpAndSettle();

    // Save entry
    await tester.tap(find.text('Zapsat do deníku'));
    await tester.pumpAndSettle();

    expect(fakeService.savedEntry, isNotNull);
    expect(fakeService.savedEntry!.amount, 12.5);
    expect(fakeService.savedEntry!.isFluidIntake, isTrue);
    expect(fakeService.savedEntry!.mealType, DiaryEntry.dinner);
    expect(fakeService.savedEntry!.date, '2026-11-01');
  });

  testWidgets('Fluid intake toggle hides when food unit is g', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DetailJidlaScreen(food: chicken),
      ),
    );

    expect(find.text('g'), findsOneWidget);
    expect(find.text('Započítat do tekutin'), findsNothing);
  });

  testWidgets('Amount smaller than 0.1 shows warning and blocks save',
      (tester) async {
    final fakeService = _FakeDiaryEntryService();
    await tester.pumpWidget(
      MaterialApp(
        home: DetailJidlaScreen(
          food: chicken,
          diaryEntryService: fakeService,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '0.05');
    await tester.pump();

    expect(find.text('Minimální množství je 0,1 g.'), findsOneWidget);

    await tester.tap(find.text('Zapsat do deníku'));
    await tester.pumpAndSettle();

    expect(fakeService.savedEntry, isNull);
    expect(find.text('Minimální množství je 0,1 g.'), findsNWidgets(2));
  });
}
