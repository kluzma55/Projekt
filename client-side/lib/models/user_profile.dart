class UserProfile {
  final int? id;
  final int? serverUserId;
  final String? email;
  final String name;
  final double weightKg;
  final double heightCm;
  final int age;
  final String gender;
  final double dailyKcalGoal;
  final double dailyProteinGoal;
  final double dailyCarbsGoal;
  final double dailyFatGoal;
  final double dailyWaterGoal; // Volitelný cíl pro příjem vody v ml

  UserProfile({
    this.id,
    this.serverUserId,
    this.email,
    required this.name,
    required this.weightKg,
    required this.heightCm,
    required this.age,
    required this.gender,
    required this.dailyKcalGoal,
    required this.dailyProteinGoal,
    required this.dailyCarbsGoal,
    required this.dailyFatGoal,
    this.dailyWaterGoal = 2000, // Defaultní hodnota pro příjem vody
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'server_user_id': serverUserId,
      'email': email,
      'name': name,
      'weight_kg': weightKg,
      'height_cm': heightCm,
      'age': age,
      'gender': gender,
      'daily_kcal_goal': dailyKcalGoal,
      'daily_protein_goal': dailyProteinGoal,
      'daily_carbs_goal': dailyCarbsGoal,
      'daily_fat_goal': dailyFatGoal,
      'daily_water_goal': dailyWaterGoal,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] as int?,
      serverUserId : map['server_user_id'] as int?,
      email: map['email'] as String?,
      name: map['name'] as String,
      weightKg: (map['weight_kg'] as num).toDouble(),
      heightCm: (map['height_cm'] as num).toDouble(),
      age: map['age'] as int,
      gender: map['gender'] as String,
      dailyKcalGoal: (map['daily_kcal_goal'] as num).toDouble(),
      dailyProteinGoal: (map['daily_protein_goal'] as num).toDouble(),
      dailyCarbsGoal: (map['daily_carbs_goal'] as num).toDouble(),
      dailyFatGoal: (map['daily_fat_goal'] as num).toDouble(),
      dailyWaterGoal: (map['daily_water_goal_ml'] as num? ?? 2000).toDouble(),
    );
  }
}