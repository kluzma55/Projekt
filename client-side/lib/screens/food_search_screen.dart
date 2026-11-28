import 'dart:async';

import 'package:flutter/material.dart';

import '../models/tables/diary_entry.dart';
import '../models/in_memory/food_search_result.dart';
import '../services/diary_entry_service.dart';
import '../services/food_search_service.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_screen_header.dart';
import 'detail_jidla_screen.dart';

/// Search screen for finding catalog and custom foods to log into the diary.
///
/// Uses [AppScreenHeader] with [AppScreenHeader.showDates] set to `false`
/// pinned at the top, a fixed search bar + results count below it, and a
/// scrollable results list in the middle.
class FoodSearchScreen extends StatefulWidget {
  final DateTime? selectedDate;
  final String initialMealType;
  final FoodSearchService? foodSearchService;
  final DiaryEntryService? diaryEntryService;

  const FoodSearchScreen({
    super.key,
    this.selectedDate,
    this.initialMealType = DiaryEntry.breakfast,
    this.foodSearchService,
    this.diaryEntryService,
  });

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  static const int _searchLimit = 50;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Timer? _debounce;
  int _searchToken = 0;
  bool _loading = false;
  bool _hasFocus = false;
  String? _error;
  List<FoodSearchResult> _results = const [];

  FoodSearchService get _searchService =>
      widget.foodSearchService ?? FoodSearchService();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (mounted) {
      setState(() => _hasFocus = _searchFocusNode.hasFocus);
    }
  }

  void _onQueryChanged(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _searchToken++;
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 120), () {
      _runSearch(value);
    });
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _searchToken++;
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }

    final token = ++_searchToken;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final items = await _searchService.searchByName(
        trimmed,
        limit: _searchLimit,
      );
      if (!mounted || token != _searchToken) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _searchToken) return;
      setState(() {
        _loading = false;
        _error = 'Nepodařilo se načíst seznam potravin.';
      });
    }
  }

  void _clearQuery() {
    _searchController.clear();
    _debounce?.cancel();
    _searchToken++;
    setState(() {
      _loading = false;
      _error = null;
      _results = const [];
    });
  }

  void _onScanEanPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Skener EAN kódů zatím není implementován.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _openDetail(FoodSearchResult food) async {
    FocusScope.of(context).unfocus();
    final savedEntry = await Navigator.push<DiaryEntry>(
      context,
      MaterialPageRoute(
        builder: (_) => DetailJidlaScreen(
          food: food,
          selectedDate: widget.selectedDate,
          initialMealType: widget.initialMealType,
          diaryEntryService: widget.diaryEntryService,
        ),
      ),
    );

    if (savedEntry != null && mounted) {
      Navigator.pop(context, savedEntry);
    }
  }

  static String _formatCount(int count) {
    if (count == 1) return '1 výsledek';
    if (count >= 2 && count <= 4) return '$count výsledky';
    return '$count výsledků';
  }

  static String _formatKcal(double kcal) {
    if (kcal == kcal.roundToDouble()) {
      return kcal.toInt().toString();
    }
    return kcal.toStringAsFixed(1).replaceAll('.', ',');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppScreenHeader(
            title: 'Hledat jídlo',
            showDates: false,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSearchBar(),
                const SizedBox(height: 18),
                _buildResultsHeader(),
              ],
            ),
          ),
          Expanded(
            child: _buildResultsBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final hasText = _searchController.text.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _hasFocus ? AppColors.green : AppColors.border,
          width: _hasFocus ? 1.5 : 1,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 14, right: 8),
              child: Icon(
                Icons.search,
                color: AppColors.green,
                size: 22,
              ),
            ),
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                onSubmitted: (val) {
                  _debounce?.cancel();
                  _runSearch(val);
                },
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.darkGreen,
                ),
                decoration: const InputDecoration(
                  hintText: 'Hledat potravinu...',
                  hintStyle: TextStyle(color: AppColors.hint),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (hasText)
              IconButton(
                onPressed: _clearQuery,
                tooltip: 'Vymazat',
                icon: const Icon(
                  Icons.close,
                  size: 19,
                  color: AppColors.muted,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: 10),
              color: AppColors.border,
            ),
            InkWell(
              onTap: _onScanEanPressed,
              borderRadius: const BorderRadius.horizontal(
                right: Radius.circular(24),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.qr_code_scanner,
                      size: 20,
                      color: AppColors.darkGreen,
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Skenovat EAN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.darkGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsHeader() {
    if (_searchController.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        const Text(
          'Nalezená jídla ',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.darkGreen,
          ),
        ),
        Text(
          '(${_formatCount(_results.length)})',
          style: const TextStyle(
            fontSize: 15,
            color: AppColors.muted,
          ),
        ),
      ],
    );
  }

  Widget _buildResultsBody() {
    if (_searchController.text.trim().isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search, size: 42, color: AppColors.muted),
              SizedBox(height: 10),
              Text(
                'Začněte psát název potraviny.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.green),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.muted),
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 42, color: AppColors.muted),
              SizedBox(height: 10),
              Text(
                'Nebyla nalezena žádná jídla.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.darkGreen,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Zkuste upravit hledaný výraz.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.muted,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        itemCount: _results.length,
        separatorBuilder: (_, _) => const Divider(
          height: 1,
          thickness: 1,
          color: AppColors.border,
        ),
        itemBuilder: (context, index) {
          final item = _results[index];
          return _buildResultTile(item);
        },
      ),
    );
  }

  Widget _buildResultTile(FoodSearchResult item) {
    return InkWell(
      onTap: () => _openDetail(item),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${_formatKcal(item.kcalPer100)} kcal',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.green,
                        ),
                      ),
                      Text(
                        ' / 100 ${item.unit}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: AppColors.lightGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chevron_right,
                size: 22,
                color: AppColors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
