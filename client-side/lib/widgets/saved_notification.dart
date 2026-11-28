import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Shows a universal confirmation banner that slides up from the bottom edge
/// whenever an entry or setting is saved (food, activity, water, weight, etc.).
///
/// Call this on the destination screen (e.g. right after `Navigator.push`
/// returns a saved result) so the banner is not obscured by pinned bottom
/// buttons and slides cleanly above any bottom navigation bar.
///
/// ## Usage example
///
/// ```dart
/// final saved = await Navigator.push<DiaryEntry>(...);
/// if (saved != null && context.mounted) {
///   showSavedNotification(context, 'Zapsáno do deníku');
/// }
///
/// // Custom duration (defaults to 3 seconds):
/// showSavedNotification(
///   context,
///   'Aktivita byla zapsána do deníku.',
///   duration: const Duration(seconds: 4),
/// );
/// ```
void showSavedNotification(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.fixed,
        backgroundColor: AppColors.green,
        duration: duration,
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: AppColors.white,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
}
