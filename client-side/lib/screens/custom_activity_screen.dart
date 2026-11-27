import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../models/activity_log.dart';

class CustomActivityScreen extends StatefulWidget {
  final DateTime? selectedDate;
  final Future<void> Function(ActivityLog) onSave;

  const CustomActivityScreen({
    super.key,
    this.selectedDate,
    required this.onSave,
  });

  @override
  State<CustomActivityScreen> createState() => _CustomActivityScreenState();
}

class _CustomActivityScreenState extends State<CustomActivityScreen> {
  static const background = Color(0xFFF6F7EF);
  static const green = Color(0xFF35634B);
  static const darkGreen = Color(0xFF233B2D);
  static const lightGreen = Color(0xFFE7EEDB);
  static const borderColor = Color(0xFFD5DACF);
  static const hintColor = Color(0xFF94998F);

  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _energy = TextEditingController();
  final _duration = TextEditingController();
  final _distance = TextEditingController();

  late final DateTime _date;
  bool _saving = false;
  bool _submitted = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _date = widget.selectedDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _name.dispose();
    _energy.dispose();
    _duration.dispose();
    _distance.dispose();
    super.dispose();
  }

  String get formattedDate {
    const days = [
      'Pondělí',
      'Úterý',
      'Středa',
      'Čtvrtek',
      'Pátek',
      'Sobota',
      'Neděle',
    ];

    const months = [
      'ledna',
      'února',
      'března',
      'dubna',
      'května',
      'června',
      'července',
      'srpna',
      'září',
      'října',
      'listopadu',
      'prosince',
    ];

    return '${days[_date.weekday - 1]} '
        '${_date.day}. ${months[_date.month - 1]} '
        '${_date.year}';
  }

  double? _parseNumber(String value) {
    return double.tryParse(value.trim().replaceAll(',', '.'));
  }

  String? _validateNumber(
    String? value, {
    bool optional = false,
    bool integer = false,
  }) {
    final text = value?.trim() ?? '';

    if (text.isEmpty) {
      return optional ? null : 'Povinný údaj';
    }

    final number = _parseNumber(text);

    if (number == null || !number.isFinite || number <= 0) {
      return 'Neplatná hodnota';
    }

    if (integer && int.tryParse(text) == null) {
      return 'Celé minuty';
    }

    return null;
  }

  Future<void> _saveActivity() async {
    if (_saving) return;

    setState(() {
      _submitted = true;
    });

    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _saveError = null;
    });

    final activity = ActivityLog(
      activityId: null,
      activityName: _name.text.trim(),
      burnedKcal: _parseNumber(_energy.text)!,
      durationMinutes: int.parse(_duration.text.trim()),
      distanceKm: _parseNumber(_distance.text),
      date:
          '${_date.year}-'
          '${_date.month.toString().padLeft(2, '0')}-'
          '${_date.day.toString().padLeft(2, '0')}',
    );

    try {
      await widget.onSave(activity);

      if (!mounted) return;

      Navigator.of(context).pop(activity);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _saving = false;
        _saveError = 'Aktivitu se nepodařilo uložit.';
      });
    }
  }

  OutlineInputBorder _border(Color color) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Form(
            key: _formKey,
            autovalidateMode: _submitted
                ? AutovalidateMode.onUserInteraction
                : AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : () => Navigator.maybePop(context),
                  icon: const Icon(Icons.chevron_left),
                  label: const Text('Zpět'),
                  style: TextButton.styleFrom(
                    foregroundColor: green,
                    padding: EdgeInsets.zero,
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  'Vlastní aktivita',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: darkGreen,
                  ),
                ),

                const SizedBox(height: 8),

                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: green,
                      size: 19,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        color: Color(0xFF858B80),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: lightGreen,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Ze seznamu',
                            style: TextStyle(color: Color(0xFF858B80)),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Center(
                            child: Text(
                              'Vlastní aktivita',
                              style: TextStyle(
                                color: green,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Název aktivity',
                  style: TextStyle(
                    fontSize: 15,
                    color: darkGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),

                const SizedBox(height: 8),

                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'Chůze',
                    hintStyle: const TextStyle(color: hintColor),
                    filled: true,
                    fillColor: Colors.white,
                    border: _border(borderColor),
                    enabledBorder: _border(borderColor),
                    focusedBorder: _border(green),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Zadejte název aktivity';
                    }

                    return null;
                  },
                ),

                const SizedBox(height: 10),

                const Text(
                  'Aktivita · podrobnosti',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: darkGreen,
                  ),
                ),

                const SizedBox(height: 10),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    children: [
                      _activityField('Vydaná energie', '30', 'kcal', _energy),
                      const Divider(color: borderColor),
                      _activityField(
                        'Doba trvání',
                        '30',
                        'min',
                        _duration,
                        integer: true,
                      ),
                      const Divider(color: borderColor),
                      _activityField(
                        'Vzdálenost',
                        '10',
                        'km',
                        _distance,
                        optional: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEBDE),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Color(0xFFB19A4A),
                        size: 22,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Zadejte pouze kalorie vydané na '
                          'aktivitu bez bazálního metabolismu. '
                          'Ten už počítáme automaticky.',
                          style: TextStyle(
                            color: darkGreen,
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_saveError != null) ...[
                  const SizedBox(height: 12),
                  Text(_saveError!, style: const TextStyle(color: Colors.red)),
                ],

                const SizedBox(height: 12),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveActivity,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: Text(
                      _saving ? 'Ukládání...' : 'Zapsat do deníku',
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
      ),

      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: background,
          border: Border(top: BorderSide(color: borderColor)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              _navigationItem(CupertinoIcons.house, 'Dnes'),
              _navigationItem(CupertinoIcons.book, 'Deník', selected: true),
              _navigationItem(CupertinoIcons.chart_bar, 'Přehled'),
              _navigationItem(CupertinoIcons.person, 'Profil'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityField(
    String label,
    String hint,
    String unit,
    TextEditingController controller, {
    bool optional = false,
    bool integer = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 16, color: darkGreen),
              ),
              if (optional)
                const Text(
                  'Nepovinné',
                  style: TextStyle(fontSize: 11, color: hintColor),
                ),
            ],
          ),
        ),
        SizedBox(
          width: 132,
          child: TextFormField(
            controller: controller,
            enabled: !_saving,
            keyboardType: TextInputType.numberWithOptions(decimal: !integer),
            textAlign: TextAlign.right,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(
                color: hintColor,
                fontStyle: FontStyle.italic,
              ),
              suffixIcon: Padding(
                padding: const EdgeInsets.only(left: 6, right: 10),
                child: Text(
                  unit,
                  style: const TextStyle(
                    color: Color(0xFF858B80),
                    fontSize: 12,
                  ),
                ),
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 0,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
              border: _border(borderColor),
              enabledBorder: _border(borderColor),
              focusedBorder: _border(green),
              errorStyle: const TextStyle(fontSize: 10),
            ),
            validator: (value) =>
                _validateNumber(value, optional: optional, integer: integer),
          ),
        ),
      ],
    );
  }

  Widget _navigationItem(IconData icon, String label, {bool selected = false}) {
    final color = selected ? green : const Color(0xFF858B80);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? lightGreen : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
