import 'package:flutter/material.dart';

import 'database/food_database.dart';
import 'models/tables/food.dart';
import 'screens/homepage.dart';
import 'widgets/app_colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _seedDemoFoodsIfEmpty();
  runApp(const MyApp());
}

Future<void> _seedDemoFoodsIfEmpty() async {
  final existing = await FoodDatabase.instance.getAllFoods();
  if (existing.isNotEmpty) return;

  final demoFoods = [
    Food(
      name: 'Polotučné mléko',
      unit: 'ml',
      kcalPer100: 47,
      proteinG: 3.3,
      carbsG: 4.8,
      sugarsG: 4.8,
      fatG: 1.5,
      saturatedFatG: 1.0,
      fibersG: 0.0,
      saltG: 0.1,
    ),
    Food(
      name: 'Grilovaná kuřecí prsa',
      unit: 'g',
      kcalPer100: 165,
      proteinG: 31.0,
      carbsG: 0.0,
      sugarsG: 0.0,
      fatG: 3.6,
      saturatedFatG: 1.0,
      fibersG: 0.0,
      saltG: 0.2,
    ),
    Food(
      name: 'Kuřecí miska s quinoou',
      unit: 'g',
      kcalPer100: 528,
      proteinG: 28.0,
      carbsG: 54.0,
      sugarsG: 4.2,
      fatG: 20.0,
      saturatedFatG: 3.5,
      fibersG: 6.5,
      saltG: 1.1,
    ),
    Food(
      name: 'Kuřecí wrap s avokádem',
      unit: 'g',
      kcalPer100: 485,
      proteinG: 24.0,
      carbsG: 42.0,
      sugarsG: 3.0,
      fatG: 22.0,
      saturatedFatG: 4.0,
      fibersG: 5.0,
      saltG: 1.3,
    ),
    Food(
      name: 'Ovesné vločky',
      unit: 'g',
      kcalPer100: 372,
      proteinG: 13.5,
      carbsG: 60.0,
      sugarsG: 1.2,
      fatG: 7.0,
      saturatedFatG: 1.3,
      fibersG: 10.0,
      saltG: 0.02,
    ),
    Food(
      name: 'Jablko',
      unit: 'g',
      kcalPer100: 52,
      proteinG: 0.3,
      carbsG: 13.8,
      sugarsG: 10.4,
      fatG: 0.2,
      saturatedFatG: 0.03,
      fibersG: 2.4,
      saltG: 0.0,
    ),
  ];

  for (final food in demoFoods) {
    await FoodDatabase.instance.insertFood(food);
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Kalorická kalkulačka',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green),
      ),
      home: const Homepage(),
    );
  }
}
