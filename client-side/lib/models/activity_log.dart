import 'activity.dart';

class ActivityLog {
  final int? id;
  final int? activityId;     // ID z katalogu ('Ze seznamu'), null pro 'Vlastní aktivita'
  final String activityName;
  final int durationMinutes;
  final double? distanceKm;
  final double burnedKcal;   // Odhadnuté nebo ručně zapsané kalorie
  final String date;

  ActivityLog({
    this.id,
    this.activityId,
    required this.activityName,
    this.durationMinutes = 0,
    this.distanceKm,
    required this.burnedKcal,
    required this.date,
  });

  bool get isCustomActivity => activityId == null;

  String get formattedPace =>
      Activity.formatAveragePace(durationMinutes, distanceKm);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'activity_id': activityId,
      'activity_name': activityName,
      'duration_minutes': durationMinutes,
      'distance_km': distanceKm,
      'burned_kcal': burnedKcal,
      'date': date,
    };
  }

  factory ActivityLog.fromMap(Map<String, dynamic> map) {
    return ActivityLog(
      id: map['id'] as int?,
      activityId: map['activity_id'] as int?,
      activityName: map['activity_name'] as String,
      durationMinutes: (map['duration_minutes'] as int?) ?? 0,
      distanceKm: (map['distance_km'] as num?)?.toDouble(),
      burnedKcal: (map['burned_kcal'] as num).toDouble(),
      date: map['date'] as String,
    );
  }

  ActivityLog copyWith({
    int? id,
    int? activityId,
    String? activityName,
    int? durationMinutes,
    double? distanceKm,
    double? burnedKcal,
    String? date,
  }) {
    return ActivityLog(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId,
      activityName: activityName ?? this.activityName,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      distanceKm: distanceKm ?? this.distanceKm,
      burnedKcal: burnedKcal ?? this.burnedKcal,
      date: date ?? this.date,
    );
  }
}