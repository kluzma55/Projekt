import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class AppBottomNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int>? onTap;

  const AppBottomNavigation({
    super.key,
    required this.selectedIndex,
    this.onTap,
  });

  static const background = Color(0xFFF6F7EF);
  static const green = Color(0xFF35634B);
  static const lightGreen = Color(0xFFE7EEDB);
  static const borderColor = Color(0xFFD5DACF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: background,
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _navigationItem(CupertinoIcons.house, 'Dnes', 0),
            _navigationItem(CupertinoIcons.book, 'Deník', 1),
            _navigationItem(CupertinoIcons.chart_bar, 'Přehled', 2),
            _navigationItem(CupertinoIcons.person, 'Profil', 3),
          ],
        ),
      ),
    );
  }

  Widget _navigationItem(IconData icon, String label, int index) {
    final selected = selectedIndex == index;
    final color = selected ? green : const Color(0xFF858B80);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap == null ? null : () => onTap!(index),
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
      ),
    );
  }
}
