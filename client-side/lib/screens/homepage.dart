import 'package:flutter/material.dart';

import '../models/tables/diary_entry.dart';
import '../services/diary_entry_service.dart';
import '../services/food_search_service.dart';
import '../widgets/app_colors.dart';
import '../widgets/saved_notification.dart';
import 'food_search_screen.dart';

/// Temporary blank homepage placeholder acting as the root screen
/// so `< Zpět` always returns here cleanly.
class Homepage extends StatelessWidget {
  final FoodSearchService? foodSearchService;
  final DiaryEntryService? diaryEntryService;

  const Homepage({
    super.key,
    this.foodSearchService,
    this.diaryEntryService,
  });

  Future<void> _openFoodSearch(BuildContext context) async {
    final savedEntry = await Navigator.push<DiaryEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          foodSearchService: foodSearchService,
          diaryEntryService: diaryEntryService,
        ),
      ),
    );

    if (savedEntry != null && context.mounted) {
      showSavedNotification(context, 'Zapsáno do deníku');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () => _openFoodSearch(context),
                icon: const Icon(Icons.add),
                label: const Text(
                  'Přidat jídlo',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.green,
                  foregroundColor: AppColors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
