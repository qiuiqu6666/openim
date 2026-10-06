// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/services/group_game_prefs.dart';
import 'package:openim/pages/group_features/sangong/utils/group_game_float_geometry.dart';

/// 群聊页可拖拽浮窗：截止 / 结算 / 报表群发 / 规则设置。
///
/// 默认收起为圆形「显」；展开为纵向圆形单字按钮（与代理反水浮窗同交互）。
/// 返回 [Positioned]，需放在 [Stack] 中。
class GroupGameFloatingEntry extends StatefulWidget {
  const GroupGameFloatingEntry({
    super.key,
    required this.theme,
    required this.conversationId,
    required this.onOpenCutoff,
    required this.onOpenSettle,
    required this.onSendSettleImage,
    required this.onSendSettleBill,
    required this.onSendPointsImage,
    required this.onSendTrendImage,
    required this.onOpenRulesSettings,
    this.settleActionLabel,
    this.setupOnly = false,
    this.onOpenSetup,
  });

  final SangongFloatTheme theme;
  final String conversationId;
  final VoidCallback onOpenCutoff;
  final VoidCallback onOpenSettle;
  final VoidCallback onSendSettleImage;
  final VoidCallback onSendSettleBill;
  final VoidCallback onSendPointsImage;
  final VoidCallback onSendTrendImage;
  final VoidCallback onOpenRulesSettings;

  /// 浮窗「结算」完整文案；已结算本局时传「冲正重结」。
  final String? settleActionLabel;

  /// 当前群查询确认 TENANT_NOT_FOUND 时，只露出「配」引导首次配置。
  final bool setupOnly;
  final VoidCallback? onOpenSetup;

  static const Color _accent = Color(0xFF1677FF);

  static const Size _collapsedSize = Size(58, 58);

  /// 8 圆钮 + 7 间距：截止/结算/结图/账单/积分/走势/设置/隐
  static const Size _expandedSize = Size(58, 534);
  static const Size _setupOnlySize = Size(58, 58);

  @override
  State<GroupGameFloatingEntry> createState() => _GroupGameFloatingEntryState();
}

class _GroupGameFloatingEntryState extends State<GroupGameFloatingEntry> {
  final GlobalKey _panelKey = GlobalKey();

  Offset? _offset;
  Size _childSize = GroupGameFloatingEntry._collapsedSize;
  bool _dragging = false;
  bool _expanded = false;
  bool _prefsLoaded = false;
  bool _positionAnimationEnabled = false;
  Size? _lastScreenSize;

  @override
  void initState() {
    super.initState();
    final saved =
        GroupGamePrefs.instance.readFloatOffsetSync(widget.conversationId);
    final expanded =
        GroupGamePrefs.instance.readFloatExpandedSync(widget.conversationId);
    if (saved != null) {
      _offset = saved;
    }
    if (expanded != null && !widget.setupOnly) {
      _expanded = expanded;
      _childSize = expanded
          ? GroupGameFloatingEntry._expandedSize
          : GroupGameFloatingEntry._collapsedSize;
    }
    unawaited(_restorePrefs());
  }

  Future<void> _restorePrefs() async {
    debugPrint('[GroupGameFloat] restore_start conv=${widget.conversationId}');
    final results = await Future.wait([
      GroupGamePrefs.instance.readFloatOffset(widget.conversationId),
      GroupGamePrefs.instance.readFloatExpanded(widget.conversationId),
    ]);
    if (!mounted) {
      return;
    }
    final saved = results[0] as Offset?;
    final expanded = widget.setupOnly ? false : results[1] as bool;
    final media = MediaQuery.of(context);
    final childSize = widget.setupOnly
        ? GroupGameFloatingEntry._setupOnlySize
        : (expanded
            ? GroupGameFloatingEntry._expandedSize
            : GroupGameFloatingEntry._collapsedSize);
    final base = saved ??
        defaultGroupGameFloatOffset(
          screenSize: media.size,
          childSize: childSize,
          bottomInset: media.viewPadding.bottom,
        );
    final next = snapGroupGameFloatOffsetToHorizontalEdge(
      offset: base,
      screenSize: media.size,
      childSize: childSize,
      viewPadding: media.viewPadding,
    );
    setState(() {
      _expanded = expanded;
      _childSize = childSize;
      _offset = next;
      _prefsLoaded = true;
    });
    debugPrint('[GroupGameFloat] restore_applied '
        'conv=${widget.conversationId} saved=$saved offset=$next '
        'expanded=$expanded');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _positionAnimationEnabled = true);
      }
    });
    if (saved == null ||
        (saved.dx - next.dx).abs() > 0.5 ||
        (saved.dy - next.dy).abs() > 0.5) {
      unawaited(GroupGamePrefs.instance
          .writeFloatOffset(widget.conversationId, next));
    }
  }

  void _measureChildIfNeeded() {
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return;
    }
    final size = box.size;
    if ((size.width - _childSize.width).abs() < 0.5 &&
        (size.height - _childSize.height).abs() < 0.5) {
      return;
    }
    final media = MediaQuery.of(context);
    final base = _offset ??
        defaultGroupGameFloatOffset(
          screenSize: media.size,
          childSize: size,
          bottomInset: media.viewPadding.bottom,
        );
    setState(() {
      _childSize = size;
      _offset = snapGroupGameFloatOffsetToHorizontalEdge(
        offset: base,
        screenSize: media.size,
        childSize: size,
        viewPadding: media.viewPadding,
      );
    });
  }

  void _ensureClampedForScreen(Size screenSize, EdgeInsets viewPadding) {
    if (_lastScreenSize == screenSize && _offset != null) {
      return;
    }
    _lastScreenSize = screenSize;
    final base = _offset ??
        defaultGroupGameFloatOffset(
          screenSize: screenSize,
          childSize: _childSize,
          bottomInset: viewPadding.bottom,
        );
    final next = snapGroupGameFloatOffsetToHorizontalEdge(
      offset: base,
      screenSize: screenSize,
      childSize: _childSize,
      viewPadding: viewPadding,
    );
    if (_offset != next) {
      _offset = next;
    }
  }

  void _toggleExpanded() {
    if (_dragging || !_prefsLoaded) {
      return;
    }
    final nextExpanded = !_expanded;
    final media = MediaQuery.of(context);
    final fallback = nextExpanded
        ? GroupGameFloatingEntry._expandedSize
        : GroupGameFloatingEntry._collapsedSize;
    final base = _offset ??
        defaultGroupGameFloatOffset(
          screenSize: media.size,
          childSize: fallback,
          bottomInset: media.viewPadding.bottom,
        );
    setState(() {
      _expanded = nextExpanded;
      _childSize = fallback;
      _offset = snapGroupGameFloatOffsetToHorizontalEdge(
        offset: base,
        screenSize: media.size,
        childSize: fallback,
        viewPadding: media.viewPadding,
      );
    });
    unawaited(GroupGamePrefs.instance
        .writeFloatExpanded(widget.conversationId, nextExpanded));
    final offset = _offset;
    if (offset != null) {
      unawaited(GroupGamePrefs.instance
          .writeFloatOffset(widget.conversationId, offset));
    }
  }

  void _onPanStart(DragStartDetails details) {
    _dragging = true;
  }

  void _onPanUpdate(
    DragUpdateDetails details,
    Size screenSize,
    EdgeInsets padding,
  ) {
    if (!_dragging) {
      return;
    }
    final current = _offset ??
        defaultGroupGameFloatOffset(
          screenSize: screenSize,
          childSize: _childSize,
          bottomInset: padding.bottom,
        );
    setState(() {
      _offset = clampGroupGameFloatOffset(
        offset: current + details.delta,
        screenSize: screenSize,
        childSize: _childSize,
        viewPadding: padding,
      );
    });
  }

  void _snapAndPersist(Size screenSize, EdgeInsets padding) {
    final current = _offset;
    if (current == null) {
      return;
    }
    final snapped = snapGroupGameFloatOffsetToHorizontalEdge(
      offset: current,
      screenSize: screenSize,
      childSize: _childSize,
      viewPadding: padding,
    );
    setState(() {
      _dragging = false;
      _offset = snapped;
    });
    unawaited(GroupGamePrefs.instance
        .writeFloatOffset(widget.conversationId, snapped));
  }

  void _onPanEnd(DragEndDetails details, Size screenSize, EdgeInsets padding) {
    _snapAndPersist(screenSize, padding);
  }

  void _onPanCancel(Size screenSize, EdgeInsets padding) {
    _snapAndPersist(screenSize, padding);
  }

  @override
  Widget build(BuildContext context) {
    // Disk state is authoritative for the first visible frame. Hiding this
    // entry briefly prevents the fallback bottom position from animating up.
    if (!_prefsLoaded) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    _ensureClampedForScreen(media.size, media.viewPadding);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _measureChildIfNeeded();
      }
    });

    final offset = _offset ??
        defaultGroupGameFloatOffset(
          screenSize: media.size,
          childSize: _childSize,
          bottomInset: media.viewPadding.bottom,
        );

    return AnimatedPositioned(
      duration: (_dragging || !_positionAnimationEnabled)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onPanStart: _onPanStart,
        onPanUpdate: (details) =>
            _onPanUpdate(details, media.size, media.viewPadding),
        onPanEnd: (details) =>
            _onPanEnd(details, media.size, media.viewPadding),
        onPanCancel: () => _onPanCancel(media.size, media.viewPadding),
        child: KeyedSubtree(
          key: _panelKey,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? SizedBox(
                    width: 58,
                    height:
                        (media.size.height - media.viewPadding.vertical - 16)
                            .clamp(58.0, 534.0),
                    child: SingleChildScrollView(child: _buildExpanded()),
                  )
                : _buildCollapsed(),
          ),
        ),
      ),
    );
  }

  Color get _primary =>
      widget.theme.primaryColor ?? GroupGameFloatingEntry._accent;

  TextStyle get _glyphStyle => TextStyle(
        fontSize: 24,
        color: _primary,
        fontWeight: FontWeight.w600,
      );

  Widget _buildCollapsed() {
    final i18n = AppI18n.of(context);
    if (widget.setupOnly) {
      return _roundButton(
        tooltip: i18n.t(
          zhHans: '三公初始配置',
          zhHant: '三公初始配置',
          en: 'Setup',
        ),
        onTap: widget.onOpenSetup ?? widget.onOpenRulesSettings,
        child: Text(
          i18n.t(zhHans: '配', zhHant: '配', en: 'S'),
          style: _glyphStyle,
        ),
      );
    }
    return _roundButton(
      tooltip: i18n.t(
        zhHans: '展开游戏功能',
        zhHant: '展開遊戲功能',
        en: 'Show',
      ),
      onTap: _toggleExpanded,
      child: Text(
        i18n.t(zhHans: '显', zhHant: '顯', en: '+'),
        style: _glyphStyle,
      ),
    );
  }

  Widget _buildExpanded() {
    final i18n = AppI18n.of(context);
    if (widget.setupOnly) {
      return _buildCollapsed();
    }
    final settleTooltip = widget.settleActionLabel ??
        i18n.t(zhHans: '结算', zhHant: '結算', en: 'Settle');
    final settleGlyph = widget.settleActionLabel != null
        ? i18n.t(zhHans: '冲', zhHant: '沖', en: 'V')
        : i18n.t(zhHans: '结', zhHant: '結', en: 'S');

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _roundButton(
          tooltip: i18n.t(zhHans: '截止', zhHant: '截止', en: 'Cutoff'),
          onTap: widget.onOpenCutoff,
          child: Text(
            i18n.t(zhHans: '截', zhHant: '截', en: 'C'),
            style: _glyphStyle,
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: settleTooltip,
          onTap: widget.onOpenSettle,
          child: Text(settleGlyph, style: _glyphStyle),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(zhHans: '结图', zhHant: '結圖', en: 'Settle image'),
          onTap: widget.onSendSettleImage,
          child: Text(
            i18n.t(zhHans: '图', zhHant: '圖', en: 'I'),
            style: _glyphStyle,
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(zhHans: '账单', zhHant: '賬單', en: 'Bill'),
          onTap: widget.onSendSettleBill,
          child: Text(
            i18n.t(zhHans: '账', zhHant: '賬', en: 'B'),
            style: _glyphStyle,
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(zhHans: '积分', zhHant: '積分', en: 'Points'),
          onTap: widget.onSendPointsImage,
          child: Text(
            i18n.t(zhHans: '分', zhHant: '分', en: 'P'),
            style: _glyphStyle,
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(zhHans: '走势图', zhHant: '走勢圖', en: 'Trend'),
          onTap: widget.onSendTrendImage,
          child: Text(
            i18n.t(zhHans: '势', zhHant: '勢', en: 'T'),
            style: _glyphStyle,
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(
            zhHans: '设置',
            zhHant: '設置',
            en: 'Settings',
            ja: '設定',
            ko: '설정',
          ),
          onTap: widget.onOpenRulesSettings,
          child: Text(
            i18n.t(zhHans: '设', zhHant: '設', en: 'G'),
            style: _glyphStyle,
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(zhHans: '收起', zhHant: '收起', en: 'Collapse'),
          onTap: _toggleExpanded,
          child: Text(
            i18n.t(zhHans: '隐', zhHant: '隱', en: '−'),
            style: _glyphStyle,
          ),
        ),
      ],
    );
  }

  Widget _roundButton({
    required String tooltip,
    required VoidCallback? onTap,
    required Widget child,
  }) {
    final isDark =
        (widget.theme.weakBackgroundColor ?? Colors.white).computeLuminance() <
            0.5;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark ? const Color(0xFF2A2A2E) : Colors.white,
        shape: const CircleBorder(),
        elevation: _dragging ? 10 : 6,
        shadowColor: isDark ? Colors.black87 : Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _dragging || !_prefsLoaded ? null : onTap,
          child: SizedBox(
            width: 58,
            height: 58,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
