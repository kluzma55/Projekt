import 'package:flutter/material.dart';
import 'models/tables/diary_entry.dart';
import 'models/in_memory/food_search_result.dart';
import 'screens/detail_jidla_screen.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DetailJidlaScreen(
        food: const FoodSearchResult(
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
        ),
        initialAmount: 250,
        initialMealType: DiaryEntry.morningSnack,
      ),
    ),
  );
}
