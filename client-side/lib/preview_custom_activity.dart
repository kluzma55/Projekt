import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/custom_activity_screen.dart';
import 'database/user_database.dart';
import 'models/activity_log.dart';

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: PreviewDiary()),
  );
}

class PreviewDiary extends StatefulWidget {
  const PreviewDiary({super.key});

  @override
  State<PreviewDiary> createState() => _PreviewDiaryState();
}

class _PreviewDiaryState extends State<PreviewDiary> {
  List<ActivityLog> _activities = [];
  double _totalBurnedKcal = 0.0;

  final _database = UserDatabase.instance;
  final _selectedDate = DateTime.now();

  String get _dateKey =>
      '${_selectedDate.year}-'
      '${_selectedDate.month.toString().padLeft(2, '0')}-'
      '${_selectedDate.day.toString().padLeft(2, '0')}';

  bool _showConfirmation = false;
  Timer? _timer;

  static const green = Color(0xFF35634B);

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  Future<void> _loadActivities() async {
    try {
      final activities = await _database.getActivityLogsByDate(_dateKey);

      final total = await _database.getTotalBurnedKcalByDate(_dateKey);

      if (!mounted) return;

      setState(() {
        _activities = activities;
        _totalBurnedKcal = total;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktivity se nepodařilo načíst.')),
      );
      debugPrint('Chyba načítání aktivit: $e');
    }
  }

  Future<void> _openActivity() async {
    final result = await Navigator.push<ActivityLog>(
      context,
      MaterialPageRoute(
        builder: (context) => CustomActivityScreen(
          selectedDate: _selectedDate,

          // Zatím pouze testovací uložení do paměti.
          onSave: (activity) async {
            await _database.insertActivityLog(activity);
          },
        ),
      ),
    );

    if (result == null || !mounted) return;

    await _loadActivities();

    if (!mounted) return;

    _timer?.cancel();

    setState(() {
      _showConfirmation = true;
    });

    _timer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showConfirmation = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7EF),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 55),
                const Text(
                  'Deník',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF233B2D),
                  ),
                ),

                const SizedBox(height: 8),

                const Text('Testovací náhled deníku'),

                const SizedBox(height: 16),

                Text(
                  'Výdej z aktivit: ${_totalBurnedKcal.toStringAsFixed(1)} kcal',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: green,
                  ),
                ),

                const SizedBox(height: 24),

                ElevatedButton.icon(
                  onPressed: _openActivity,
                  icon: const Icon(Icons.add),
                  label: const Text('Přidat vlastní aktivitu'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                  ),
                ),

                const SizedBox(height: 24),

                for (final activity in _activities)
                  Card(
                    color: Colors.white,
                    child: ListTile(
                      leading: const Icon(Icons.directions_walk, color: green),
                      title: Text(activity.activityName),
                      subtitle: Text('${activity.durationMinutes} min'),
                      trailing: Text(
                        '${activity.burnedKcal.toStringAsFixed(1)} kcal',
                      ),
                    ),
                  ),
              ],
            ),

            if (_showConfirmation)
              Positioned(
                top: 12,
                left: 20,
                right: 20,
                child: Material(
                  color: green,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: Colors.white,
                          size: 21,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Aktivita byla zapsána do deníku.',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
