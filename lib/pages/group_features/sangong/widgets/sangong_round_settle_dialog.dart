// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/utils/keypad_feedback.dart';
import 'package:openim/pages/group_features/sangong/utils/sangong_draw_input_format.dart';
import '../sangong_scope.dart';
import 'authorization/privilege_route_guard.dart';

/// 录入各门开彩（00～99），内置数字键盘，不唤起系统键盘。
class SangongRoundSettleDialog extends StatefulWidget {
  const SangongRoundSettleDialog({
    super.key,
    required this.drawStatus,
    this.clearExisting = false,
    this.titleText,
    this.subtitleText,
    this.confirmLabel,
  });

  final SangongDrawStatus drawStatus;

  /// 冲正重结：不回填旧开奖号码。
  final bool clearExisting;
  final String? titleText;
  final String? subtitleText;
  final String? confirmLabel;

  static Future<List<SangongDrawInput>?> show(
    BuildContext context, {
    required SangongDrawStatus drawStatus,
    bool clearExisting = false,
    String? titleText,
    String? subtitleText,
    String? confirmLabel,
  }) {
    final runtime = SangongScope.read(context);
    final featureContext = runtime.featureContext;
    if (!runtime.canManage) return Future.value(null);
    return showModalBottomSheet<List<SangongDrawInput>>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => SangongPrivilegeRouteGuard(
        featureContext: featureContext,
        refreshOnEntry: false,
        isCurrent: () => runtime.canManage,
        builder: (_) => SangongScope(
          runtime: runtime,
          child: SangongRoundSettleDialog(
            drawStatus: drawStatus,
            clearExisting: clearExisting,
            titleText: titleText,
            subtitleText: subtitleText,
            confirmLabel: confirmLabel,
          ),
        ),
      ),
    );
  }

  @override
  State<SangongRoundSettleDialog> createState() =>
      _SangongRoundSettleDialogState();
}

class _SangongRoundSettleDialogState extends State<SangongRoundSettleDialog> {
  late final List<int> _doors;
  late final Map<int, TextEditingController> _controllers;
  late int _activeIndex;
  final ScrollController _doorScrollController = ScrollController();
  final Map<int, GlobalKey> _doorItemKeys = {};

  @override
  void initState() {
    super.initState();
    _doors = widget.drawStatus.doorsToEnter.reversed.toList();
    _controllers = {};
    for (final door in _doors) {
      var initial = '';
      if (!widget.clearExisting) {
        final existing = widget.drawStatus.drawForDoor(door);
        final initialRaw = existing?.rawInput.trim().isNotEmpty == true
            ? existing!.rawInput.trim()
            : (existing?.amount.trim().isNotEmpty == true
                ? existing!.amount.trim()
                : '');
        initial = SangongDrawInputFormat.sanitizeInitial(initialRaw);
      }
      _controllers[door] = TextEditingController(text: initial);
    }
    _activeIndex = _firstIncompleteIndex(fallback: 0);
    for (var i = 0; i < _doors.length; i++) {
      _doorItemKeys[i] = GlobalKey();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollActiveDoorIntoView();
    });
  }

  int _firstIncompleteIndex({required int fallback}) {
    for (var i = 0; i < _doors.length; i++) {
      final text = _controllers[_doors[i]]?.text ?? '';
      if (!SangongDrawInputFormat.isValidEntry(text)) {
        return i;
      }
    }
    return fallback.clamp(0, _doors.length - 1);
  }

  @override
  void dispose() {
    _doorScrollController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _scrollActiveDoorIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final itemKey = _doorItemKeys[_activeIndex];
      final itemContext = itemKey?.currentContext;
      if (itemContext == null) {
        return;
      }
      final alignment = _activeIndex >= _doors.length - 2 ? 0.72 : 0.35;
      Scrollable.ensureVisible(
        itemContext,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        alignment: alignment,
      );
    });
  }

  int get _activeDoor => _doors[_activeIndex];

  TextEditingController get _activeController => _controllers[_activeDoor]!;

  void _selectDoor(int index) {
    if (index < 0 || index >= _doors.length) {
      return;
    }
    setState(() => _activeIndex = index);
    _scrollActiveDoorIntoView();
  }

  void _appendDigit(String digit) {
    final controller = _activeController;
    var current = controller.text;
    // 已录满两位时，新输入从当前门重新开始（便于改错）。
    if (current.length >= 2) {
      current = '';
    }
    final next = SangongDrawInputFormat.appendDigit(current, digit);
    if (next == controller.text) {
      return;
    }
    controller.text = next;
    controller.selection = TextSelection.collapsed(offset: next.length);
    setState(() {});
    if (next.length == 2 && _activeIndex < _doors.length - 1) {
      _selectDoor(_activeIndex + 1);
    }
  }

  void _deleteLast() {
    final controller = _activeController;
    if (controller.text.isEmpty) {
      if (_activeIndex > 0) {
        final prevIndex = _activeIndex - 1;
        final prevDoor = _doors[prevIndex];
        final prevController = _controllers[prevDoor]!;
        final next = SangongDrawInputFormat.deleteLast(prevController.text);
        setState(() => _activeIndex = prevIndex);
        if (next != prevController.text) {
          prevController.text = next;
          prevController.selection =
              TextSelection.collapsed(offset: next.length);
        }
      }
      return;
    }
    final next = SangongDrawInputFormat.deleteLast(controller.text);
    if (next == controller.text) {
      return;
    }
    controller.text = next;
    controller.selection = TextSelection.collapsed(offset: next.length);
    setState(() {});
  }

  String _doorLabel(int door) {
    return AppI18n.of(context).t(
      zhHans: '$door门',
      zhHant: '$door門',
      en: 'D$door',
    );
  }

  List<String> _normalizedEntries() {
    return _doors
        .map((door) => SangongDrawInputFormat.normalizeForSubmit(
              _controllers[door]?.text ?? '',
            ))
        .where((value) => value.isNotEmpty)
        .toList();
  }

  bool get _allDoorsFilled => _normalizedEntries().length == _doors.length;

  int get _tailSumCheckDigit {
    if (!_allDoorsFilled) {
      return -1;
    }
    return SangongDrawInputFormat.tailSumCheckDigit(_normalizedEntries());
  }

  List<SangongDrawInput>? _readDrawInputs() {
    final inputs = <SangongDrawInput>[];
    for (final door in _doors) {
      final raw = _controllers[door]?.text ?? '';
      final normalized = SangongDrawInputFormat.normalizeForSubmit(raw);
      if (normalized.isEmpty) {
        return null;
      }
      inputs.add(SangongDrawInput(door: door, amount: normalized));
    }
    return inputs;
  }

  void _onConfirm() {
    final inputs = _readDrawInputs();
    if (inputs == null) {
      ToastUtils.toast(
        AppI18n.of(context).t(
          zhHans: '请为每一门输入 00～99',
          zhHant: '請為每一門輸入 00～99',
          en: 'Enter 00–99 for each door',
        ),
      );
      _selectDoor(_firstIncompleteIndex(fallback: _activeIndex));
      return;
    }
    if (!SangongDrawInputFormat.isTailSumValid(
      inputs.map((e) => e.amount),
    )) {
      final sum =
          SangongDrawInputFormat.sumTailDigits(inputs.map((e) => e.amount));
      ToastUtils.toast(
        AppI18n.of(context).t(
          zhHans: '各门尾数之和须为 0（或 10、20…），当前合计 $sum',
          zhHant: '各門尾數之和須為 0（或 10、20…），當前合計 $sum',
          en: 'Sum of ones digits must end in 0 (current total: $sum)',
        ),
      );
      return;
    }
    Navigator.of(context).pop(inputs);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppColors.card(dark: dark);
    final titleColor = AppColors.text(dark: dark);
    final subColor = AppColors.subText(dark: dark);
    final borderColor = AppColors.line(dark: dark);
    final i18n = AppI18n.of(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final sheetHeight = (screenHeight * 0.78).clamp(480.0, screenHeight * 0.92);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: sheetHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(i18n, titleColor, subColor),
              Expanded(
                child: SingleChildScrollView(
                  controller: _doorScrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: _buildDoorList(
                    titleColor: titleColor,
                    subColor: subColor,
                    borderColor: borderColor,
                  ),
                ),
              ),
              Divider(height: 1, color: borderColor),
              SafeArea(
                top: false,
                child: _buildKeypad(dark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppI18n i18n, Color titleColor, Color subColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.titleText ??
                      i18n.t(
                        zhHans: '录入开彩',
                        zhHant: '錄入開彩',
                        en: 'Enter draws',
                      ),
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.subtitleText ??
                      i18n.t(
                        zhHans: '每门 00～99，全部尾数之和须为 0',
                        zhHant: '每門 00～99，全部尾數之和須為 0',
                        en: '00–99 per door; ones digits must sum to 0',
                      ),
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
                if (_allDoorsFilled) ...[
                  const SizedBox(height: 4),
                  Text(
                    _tailSumCheckDigit == 0
                        ? i18n.t(
                            zhHans: '尾数校验通过',
                            zhHant: '尾數校驗通過',
                            en: 'Ones-digit check passed',
                          )
                        : i18n.t(
                            zhHans:
                                '尾数合计 ${SangongDrawInputFormat.sumTailDigits(_normalizedEntries())}，须为 0/10/20…',
                            zhHant:
                                '尾數合計 ${SangongDrawInputFormat.sumTailDigits(_normalizedEntries())}，須為 0/10/20…',
                            en: 'Ones-digit total ${SangongDrawInputFormat.sumTailDigits(_normalizedEntries())} must end in 0',
                          ),
                    style: TextStyle(
                      color: _tailSumCheckDigit == 0
                          ? AppColors.success
                          : AppColors.primaryRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(i18n.t(zhHans: '取消', zhHant: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: _onConfirm,
            child: Text(
              widget.confirmLabel ??
                  i18n.t(zhHans: '结算', zhHant: '結算', en: 'Settle'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoorList({
    required Color titleColor,
    required Color subColor,
    required Color borderColor,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _doors.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          KeyedSubtree(
            key: _doorItemKeys[i],
            child: _buildDoorField(
              door: _doors[i],
              index: i,
              titleColor: titleColor,
              subColor: subColor,
              borderColor: borderColor,
              active: i == _activeIndex,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDoorField({
    required int door,
    required int index,
    required Color titleColor,
    required Color subColor,
    required Color borderColor,
    required bool active,
  }) {
    final existing = widget.drawStatus.drawForDoor(door);
    final controller = _controllers[door]!;
    final isBanker = widget.drawStatus.bankerDoor == door;
    final activeBorder = active ? AppColors.primaryBlue : borderColor;
    final activeFill = active
        ? AppColors.primaryBlue.withValues(alpha: 0.08)
        : _bankerFill(isBanker);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _selectDoor(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: activeFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: activeBorder,
              width: active ? 2 : 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.12),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  _doorLabel(door),
                  style: TextStyle(
                    color: isBanker ? AppColors.primaryBlue : titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: IgnorePointer(
                  child: TextField(
                    controller: controller,
                    readOnly: true,
                    showCursor: active,
                    enableInteractiveSelection: false,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: titleColor,
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                    decoration: InputDecoration(
                      hintText: '00',
                      hintStyle: TextStyle(
                        color: subColor.withValues(alpha: 0.45),
                        fontSize: 22,
                        letterSpacing: 2,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    ),
                  ),
                ),
              ),
              if (existing != null && existing.handLabel.trim().isNotEmpty)
                SizedBox(
                  width: 36,
                  child: Text(
                    existing.handLabel.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(color: subColor, fontSize: 11),
                  ),
                )
              else
                const SizedBox(width: 36),
            ],
          ),
        ),
      ),
    );
  }

  Color _bankerFill(bool isBanker) {
    if (!isBanker) {
      return Colors.transparent;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AppColors.primaryBlue.withValues(alpha: isDark ? 0.06 : 0.04);
  }

  Widget _buildKeypad(bool dark) {
    final keyBg = dark ? const Color(0xFF2C2C30) : const Color(0xFFF2F3F5);
    final keyStyle = TextStyle(
      color: AppColors.text(dark: dark),
      fontSize: 22,
      fontWeight: FontWeight.w500,
    );

    Widget key({
      required Widget child,
      required VoidCallback onTap,
      required VoidCallback onFeedback,
      int flex = 1,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Material(
            color: keyBg,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                onFeedback();
                onTap();
              },
              child: SizedBox(
                height: 46,
                child: Center(child: child),
              ),
            ),
          ),
        ),
      );
    }

    Widget digitKey(String digit) {
      return key(
        child: Text(digit, style: keyStyle),
        onFeedback: KeypadFeedback.digitTap,
        onTap: () => _appendDigit(digit),
      );
    }

    // 底行：左侧空位 · 中间 0 · 右侧删除（录满两位仍自动跳下一门；结算走顶栏按钮）。
    Widget emptySlot() {
      return const Expanded(
        child: Padding(
          padding: EdgeInsets.all(4),
          child: SizedBox(height: 46),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Column(
        children: [
          Row(
            children: [
              digitKey('1'),
              digitKey('2'),
              digitKey('3'),
            ],
          ),
          Row(
            children: [
              digitKey('4'),
              digitKey('5'),
              digitKey('6'),
            ],
          ),
          Row(
            children: [
              digitKey('7'),
              digitKey('8'),
              digitKey('9'),
            ],
          ),
          Row(
            children: [
              emptySlot(),
              digitKey('0'),
              key(
                child: Icon(
                  Icons.backspace_outlined,
                  color: AppColors.text(dark: dark),
                  size: 22,
                ),
                onFeedback: KeypadFeedback.deleteTap,
                onTap: _deleteLast,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
