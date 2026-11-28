import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Reusable pinned bottom "Zapsat do deníku" action bar.
///
/// Renders a top divider and a full-width dark-green button inside a bottom
/// [SafeArea]. Place it as the last child of a [Column] below an [Expanded]
/// scrollable body so it stays pinned at the bottom of the screen.
///
/// ## Usage example
///
/// ```dart
/// Column(
///   children: [
///     AppScreenHeader(title: 'Detail jídla'),
///     Expanded(child: SingleChildScrollView(child: ...)),
///     SaveEntryButton(
///       onPressed: _save,
///       loading: _saving,
///       errorMessage: _validationError,
///       // label: 'Uložit změny', // optional override
///     ),
///   ],
/// )
/// ```
///
/// - Set [loading] to `true` while an async save is running to disable taps
///   and display a spinner.
/// - Pass [errorMessage] to show a red validation/error message directly above
///   the button.
class SaveEntryButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool loading;
  final String? errorMessage;
  final String label;

  const SaveEntryButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.errorMessage,
    this.label = 'Zapsat do deníku',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.border,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorMessage != null) ...[
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 6),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: loading ? null : onPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.green,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.green.withValues(alpha: 0.6),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              label,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
