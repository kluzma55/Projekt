import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Reusable pinned top header used across screens (food search, food detail,
/// activity detail, etc.).
///
/// Place it as the first child of a [Column] above an [Expanded] scrollable
/// body so it stays pinned at the top with a bottom divider.
///
/// ## Usage example
///
/// ```dart
/// // 1. Detail screen with date pill:
/// AppScreenHeader(
///   title: 'Detail jídla',
///   createdAt: selectedDate, // defaults to DateTime.now() if omitted
///   onBack: () => Navigator.of(context).popUntil((r) => r.isFirst),
/// )
///
/// // 2. Search screen without date pill (keeps identical spacing & height):
/// const AppScreenHeader(
///   title: 'Hledat jídlo',
///   showDates: false,
/// )
/// ```
///
/// - [showDates] defaults to `true`. Set it to `false` to hide the green date
///   pill while preserving the exact same header height and title spacing.
/// - [onBack] defaults to `Navigator.maybePop(context)`. Pass a custom callback
///   if `< Zpět` should jump to a specific route (e.g. `popUntil(isFirst)`).
class AppScreenHeader extends StatelessWidget {
  final String title;

  /// The entry creation date shown in the green pill.
  final DateTime? createdAt;

  /// Whether to show the date pill on the right.
  final bool showDates;

  /// Optional custom back callback; defaults to [Navigator.maybePop].
  final VoidCallback? onBack;

  const AppScreenHeader({
    super.key,
    required this.title,
    this.createdAt,
    this.showDates = true,
    this.onBack,
  });

  static const _months = [
    'led', 'úno', 'bře', 'dub', 'kvě', 'čvn',
    'čvc', 'srp', 'zář', 'říj', 'lis', 'pro',
  ];

  static String _formatDate(DateTime d) =>
      '${d.day}. ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final cre = createdAt ?? DateTime.now();

    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed:
                            onBack ?? () => Navigator.maybePop(context),
                        icon: const Icon(Icons.chevron_left, size: 22),
                        label: const Text('Zpět'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.green,
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Spacer(),
                      if (showDates)
                        _datePill(_formatDate(cre))
                      else
                        // Keep identical row height when date pill is hidden.
                        ExcludeSemantics(
                          child: Opacity(
                            opacity: 0,
                            child: _pillHeightPlaceholder(),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkGreen,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              thickness: 1,
              color: AppColors.border,
            ),
          ],
        ),
      ),
    );
  }

  static Widget _pillHeightPlaceholder() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(width: 0, height: 15),
          Text(
            '',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  static Widget _datePill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.lightGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_month_outlined,
            size: 15,
            color: AppColors.green,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.darkGreen,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
