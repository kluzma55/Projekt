import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/tables/diary_entry.dart';
import '../models/in_memory/food_search_result.dart';
import '../services/diary_entry_service.dart';
import '../widgets/app_colors.dart';
import '../widgets/app_screen_header.dart';
import '../widgets/save_entry_button.dart';

/// Allows only digits and at most one decimal dot `.`.
class _DecimalNumberInputFormatter extends TextInputFormatter {
  static final _validPattern = RegExp(r'^\d*\.?\d*$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (_validPattern.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}

/// Screen for viewing food details, adjusting amount/meal type,
/// and logging the entry into the food diary.
class DetailJidlaScreen extends StatefulWidget {
  final FoodSearchResult food;
  final DateTime? selectedDate;
  final DateTime? createdAt;
  final String initialMealType;
  final double initialAmount;
  final DiaryEntryService? diaryEntryService;

  const DetailJidlaScreen({
    super.key,
    required this.food,
    this.selectedDate,
    this.createdAt,
    this.initialMealType = DiaryEntry.breakfast,
    this.initialAmount = 100,
    this.diaryEntryService,
  });

  @override
  State<DetailJidlaScreen> createState() => _DetailJidlaScreenState();
}

class _DetailJidlaScreenState extends State<DetailJidlaScreen> {
  late final TextEditingController _amountController;
  late final FocusNode _amountFocusNode;
  late bool _isFluidIntake;
  late String _mealType;
  late Map<String, double> _nutrition;

  bool _showDetails = false;
  bool _saving = false;
  bool _amountFocused = false;
  String? _error;

  DiaryEntryService get _service =>
      widget.diaryEntryService ?? DiaryEntryService();

  bool get _isLiquid => widget.food.unit.trim().toLowerCase() == 'ml';

  @override
  void initState() {
    super.initState();
    _isFluidIntake = _isLiquid;
    _mealType = DiaryEntry.allowedMealTypes.contains(widget.initialMealType)
        ? widget.initialMealType
        : DiaryEntry.breakfast;
    _amountController = TextEditingController(
      text: _formatInputAmount(widget.initialAmount),
    );
    _amountFocusNode = FocusNode()..addListener(_onAmountFocusChange);
    _nutrition = widget.food.nutritionFor(widget.initialAmount);
    _amountController.addListener(_onAmountChanged);
  }

  @override
  void dispose() {
    _amountFocusNode.removeListener(_onAmountFocusChange);
    _amountFocusNode.dispose();
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    super.dispose();
  }

  void _onAmountFocusChange() {
    if (mounted) {
      setState(() => _amountFocused = _amountFocusNode.hasFocus);
    }
  }

  static String _formatInputAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  /// Formats a number with Czech decimal comma, trimming trailing zeros.
  static String _formatNumber(double? value, {int decimals = 1}) {
    if (value == null) return '-';
    final fixed = value.toStringAsFixed(decimals);
    final trimmed = fixed.contains('.')
        ? fixed.replaceFirst(RegExp(r'\.?0+$'), '')
        : fixed;
    return trimmed.replaceAll('.', ',');
  }

  void _onAmountChanged() {
    final parsed = double.tryParse(_amountController.text.trim());
    setState(() {
      _error = null;
      if (parsed != null && parsed > 0) {
        _nutrition = widget.food.nutritionFor(parsed);
      } else {
        _nutrition = widget.food.nutritionFor(0);
      }
    });
  }

  Future<void> _pickMealType() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text(
                      'Zařadit do jídla',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.darkGreen,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => Navigator.pop(sheetContext),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: AppColors.foodCardBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppColors.darkGreen,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < DiaryEntry.allowedMealTypes.length; i++) ...[
                  if (i > 0 &&
                      DiaryEntry.allowedMealTypes[i] != _mealType &&
                      DiaryEntry.allowedMealTypes[i - 1] != _mealType)
                    const Divider(height: 1, color: AppColors.border),
                  _mealOptionTile(
                    sheetContext,
                    DiaryEntry.allowedMealTypes[i],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );

    if (chosen != null && mounted) {
      setState(() {
        _mealType = chosen;
      });
    }
  }

  Widget _mealOptionTile(BuildContext sheetContext, String meal) {
    final isSelected = meal == _mealType;
    return InkWell(
      onTap: () => Navigator.pop(sheetContext, meal),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.lightGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Text(
              meal,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: AppColors.darkGreen,
              ),
            ),
            const Spacer(),
            if (isSelected)
              const Icon(Icons.check, size: 20, color: AppColors.green),
          ],
        ),
      ),
    );
  }

  String? get _inlineAmountWarning {
    final text = _amountController.text.trim();
    if (text.isEmpty || text == '0' || text.endsWith('.')) return null;
    final parsed = double.tryParse(text);
    if (parsed != null && parsed < DiaryEntryService.minAmount) {
      return 'Minimální množství je 0,1 ${widget.food.unit}.';
    }
    return null;
  }

  String _formatErrors(List<DiaryEntryError> errors) {
    if (errors.contains(DiaryEntryError.invalidAmount)) {
      return 'Minimální množství je 0,1 ${widget.food.unit}.';
    }
    if (errors.contains(DiaryEntryError.invalidAmountFormat)) {
      return 'Zadejte prosím platné množství.';
    }
    if (errors.contains(DiaryEntryError.invalidDate)) {
      return 'Neplatné datum záznamu.';
    }
    if (errors.contains(DiaryEntryError.invalidMealType)) {
      return 'Vyberte platný typ jídla.';
    }
    return 'Záznam se nepodařilo uložit.';
  }

  Future<void> _save() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _error = null;
    });

    final d = widget.selectedDate ?? DateTime.now();
    final dateStr =
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    try {
      final result = await _service.saveEntry(
        selectedFood: widget.food,
        amountText: _amountController.text,
        mealType: _mealType,
        date: dateStr,
        isFluidIntake: _isLiquid ? _isFluidIntake : false,
      );

      if (!mounted) return;

      if (result.isValid) {
        final popped = await Navigator.maybePop(context, result.entry);
        if (!popped && mounted) {
          setState(() => _saving = false);
        }
      } else {
        setState(() {
          _saving = false;
          _error = _formatErrors(result.errors);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Záznam se nepodařilo uložit do deníku.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          AppScreenHeader(
            title: 'Detail jídla',
            createdAt: widget.createdAt,
            onBack: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFoodCard(),
                  const SizedBox(height: 16),
                  _buildAmountField(),
                  if (_isLiquid) ...[
                    const SizedBox(height: 14),
                    _buildFluidIntakeToggle(),
                  ],
                  const SizedBox(height: 12),
                  _buildMealTypeSelector(),
                  const SizedBox(height: 14),
                  _buildNutritionCard(),
                ],
              ),
            ),
          ),
          SaveEntryButton(
            onPressed: _save,
            loading: _saving,
            errorMessage: _error,
          ),
        ],
      ),
    );
  }

  Widget _buildFoodCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.foodCardBg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.food.name,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: AppColors.darkGreen,
            ),
          ),
          const SizedBox(height: 4),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text:
                      '${_formatNumber(widget.food.kcalPer100, decimals: 0)} kcal',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.green,
                  ),
                ),
                TextSpan(
                  text: ' / 100 ${widget.food.unit}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    color: AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Množství',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.darkGreen,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _saving
              ? null
              : () {
                  _amountFocusNode.requestFocus();
                  SystemChannels.textInput.invokeMethod('TextInput.show');
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _amountFocused ? AppColors.green : AppColors.border,
                width: _amountFocused ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    focusNode: _amountFocusNode,
                    enabled: !_saving,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    inputFormatters: [_DecimalNumberInputFormatter()],
                    textInputAction: TextInputAction.done,
                    onTapOutside: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.darkGreen,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.food.unit,
                  style: const TextStyle(
                    fontSize: 16,
                    color: AppColors.darkGreen,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_inlineAmountWarning != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              _inlineAmountWarning!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFluidIntakeToggle() {
    return InkWell(
      onTap: _saving
          ? null
          : () => setState(() => _isFluidIntake = !_isFluidIntake),
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.lightGreen,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: _isFluidIntake ? AppColors.green : AppColors.white,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: _isFluidIntake ? AppColors.green : AppColors.border,
                ),
              ),
              child: _isFluidIntake
                  ? const Icon(Icons.check, size: 17, color: AppColors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            const Text(
              'Započítat do tekutin',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.darkGreen,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealTypeSelector() {
    return InkWell(
      onTap: _saving ? null : _pickMealType,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            const Text(
              'Zařadit do: ',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.darkGreen,
              ),
            ),
            Expanded(
              child: Text(
                _mealType,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                  color: AppColors.darkGreen,
                ),
              ),
            ),
            Container(
              width: 1,
              height: 20,
              color: AppColors.border,
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.keyboard_arrow_down,
              color: AppColors.green,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutritionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Text(
                'Energie',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGreen,
                ),
              ),
              const Spacer(),
              Text(
                _formatNumber(_nutrition['kcal'], decimals: 0),
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: AppColors.darkGreen,
                ),
              ),
              const Text(
                ' kcal',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: AppColors.darkGreen,
                ),
              ),
            ],
          ),
          const Divider(color: AppColors.border, height: 20),
          if (!_showDetails)
            IntrinsicHeight(
              child: Row(
                children: [
                  _macroColumn('Bílkoviny', _nutrition['protein_g']),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppColors.border,
                    indent: 6,
                    endIndent: 2,
                  ),
                  _macroColumn('Sacharidy', _nutrition['carbs_g']),
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: AppColors.border,
                    indent: 6,
                    endIndent: 2,
                  ),
                  _macroColumn('Tuky', _nutrition['fat_g']),
                ],
              ),
            )
          else ...[
            _detailRow('Bílkoviny', _nutrition['protein_g']),
            const Divider(color: AppColors.border, height: 14),
            _detailRow('Sacharidy', _nutrition['carbs_g']),
            const SizedBox(height: 4),
            _detailRow('z toho cukry', _nutrition['sugars_g'], indented: true),
            const Divider(color: AppColors.border, height: 14),
            _detailRow('Tuky', _nutrition['fat_g']),
            const SizedBox(height: 4),
            _detailRow(
              'z toho nasycené mastné kyseliny',
              _nutrition['saturated_fat_g'],
              indented: true,
            ),
            const Divider(color: AppColors.border, height: 14),
            _detailRow('Vláknina', _nutrition['fibers_g']),
            const Divider(color: AppColors.border, height: 14),
            _detailRow('Sůl', _nutrition['salt_g'], decimals: 2),
          ],
          const SizedBox(height: 14),
          InkWell(
            onTap: () => setState(() => _showDetails = !_showDetails),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.lightGreen,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Text(
                    _showDetails ? 'Skrýt podrobnosti' : 'Zobrazit podrobnosti',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 1,
                    height: 18,
                    color: AppColors.border,
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _showDetails
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.green,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroColumn(String label, double? value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.muted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatNumber(value)} g',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.darkGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    double? value, {
    bool indented = false,
    int decimals = 1,
  }) {
    final text =
        value == null ? '- g' : '${_formatNumber(value, decimals: decimals)} g';
    return Padding(
      padding: EdgeInsets.only(left: indented ? 14 : 0, top: 2, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: indented ? 14 : 15,
                color: indented ? AppColors.muted : AppColors.darkGreen,
                fontWeight: indented ? FontWeight.w400 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            text,
            style: TextStyle(
              fontSize: indented ? 14 : 15,
              color: AppColors.darkGreen,
              fontWeight: indented ? FontWeight.w400 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
