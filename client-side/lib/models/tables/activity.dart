class Activity {
  final int? id;
  final String name;
  final double kcalPerHourPerKg; // Base expenditure coefficient (MET)
  final bool hasDistance;        // True = Distance and Average pace are shown in UI

  Activity({
    this.id,
    required this.name,
    required this.kcalPerHourPerKg,
    this.hasDistance = false,
  });

  /// Formatting average pace for UI (e.g. 30 min and 5 km -> "6:00 min/km")
  static String formatAveragePace(int durationMinutes, double? distanceKm) {
    if (distanceKm == null || distanceKm <= 0 || durationMinutes <= 0) {
      return '--:-- min/km';
    }
    final paceDecimal = durationMinutes / distanceKm;
    final mins = paceDecimal.floor();
    final secs = ((paceDecimal - mins) * 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')} min/km';
  }

  /// Estimate of expended energy based on duration, distance (pace), and UserProfile data
  double calculateBurnedKcal({
    required int durationMinutes,
    double? distanceKm,
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
  }) {
    final hours = durationMinutes / 60.0;
    if (hours <= 0) return 0.0;

    // 1. Coefficient adjustment by pace, if distance is provided
    double effectiveCoeff = kcalPerHourPerKg;
    if (hasDistance && distanceKm != null && distanceKm > 0) {
      final speedKmh = distanceKm / hours;
      final lowerName = name.toLowerCase();
      if (lowerName.contains('běh')) {
        effectiveCoeff = (speedKmh * 1.12).clamp(6.0, 18.0);
      } else if (lowerName.contains('chůze')) {
        effectiveCoeff = (speedKmh * 0.85).clamp(2.5, 8.0);
      } else if (lowerName.contains('kolo') || lowerName.contains('cyklistika')) {
        effectiveCoeff = (speedKmh * 0.42).clamp(4.0, 16.0);
      }
    }

    // 2. Basal expenditure by weight, height, age, and gender (Mifflin-St Jeor)
    final isFemale = gender.toUpperCase() == 'F' || gender.toLowerCase() == 'žena';
    final bmrPerDay = (10 * weightKg) +
        (6.25 * heightCm) -
        (5 * age) +
        (isFemale ? -161 : 5);
    final bmrPerHour = bmrPerDay / 24.0;

    // 3. Total estimate of expended energy rounded to whole kcal
    final kcal = bmrPerHour * effectiveCoeff * hours;
    return kcal.roundToDouble();
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'kcal_per_hour_per_kg': kcalPerHourPerKg,
      'has_distance': hasDistance ? 1 : 0,
    };
  }

  factory Activity.fromMap(Map<String, dynamic> map) {
    return Activity(
      id: map['id'] as int?,
      name: map['name'] as String,
      kcalPerHourPerKg: (map['kcal_per_hour_per_kg'] as num).toDouble(),
      hasDistance: (map['has_distance'] as int? ?? 0) == 1,
    );
  }
}