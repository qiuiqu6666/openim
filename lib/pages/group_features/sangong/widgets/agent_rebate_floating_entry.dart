// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';
import 'package:openim/pages/group_features/sangong/services/agent_rebate_float_prefs.dart';
import 'package:openim/pages/group_features/sangong/utils/group_game_float_geometry.dart';

enum AgentRebateFloatingVariant { game, sangong }

/// 群聊页代理查询浮窗：查下级 / 历史记录。
///
/// 首次展开状态由调用方指定，之后记住用户选择；拖动后吸附到左右边缘。
class AgentRebateFloatingEntry extends StatefulWidget {
  const AgentRebateFloatingEntry({
    super.key,
    required this.theme,
    required this.conversationId,
    required this.onOpenDescendants,
    required this.onOpenRebate,
    required this.onOpenHistory,
    this.variant = AgentRebateFloatingVariant.game,
    this.defaultBottom = 220,
    this.defaultExpanded = false,
  });

  final SangongFloatTheme theme;
  final String conversationId;
  final VoidCallback onOpenDescendants;
  final VoidCallback onOpenRebate;
  final VoidCallback onOpenHistory;
  final AgentRebateFloatingVariant variant;
  final double defaultBottom;
  final bool defaultExpanded;

  static const Size _collapsedSize = Size(58, 58);
  static const Size _expandedSize = Size(58, 262);

  @override
  State<AgentRebateFloatingEntry> createState() =>
      _AgentRebateFloatingEntryState();
}

class _AgentRebateFloatingEntryState extends State<AgentRebateFloatingEntry> {
  final GlobalKey _panelKey = GlobalKey();

  Offset? _offset;
  Offset? _preferredOffset;
  Size _childSize = AgentRebateFloatingEntry._collapsedSize;
  Size? _lastScreenSize;
  EdgeInsets? _lastPadding;
  bool _dragging = false;
  bool _expanded = false;
  bool _prefsLoaded = false;
  bool _positionAnimationEnabled = false;

  @override
  void initState() {
    super.initState();
    final saved =
        AgentRebateFloatPrefs.instance.readOffsetSync(widget.conversationId);
    final expanded = AgentRebateFloatPrefs.instance
            .readExpandedSync(widget.conversationId) ??
        widget.defaultExpanded;
    if (saved != null) {
      _offset = saved;
      _preferredOffset = saved;
    }
    _expanded = expanded;
    _childSize = expanded
        ? AgentRebateFloatingEntry._expandedSize
        : AgentRebateFloatingEntry._collapsedSize;
    unawaited(_restorePrefs());
  }

  Future<void> _restorePrefs() async {
    debugPrint(
        '[AgentRebateFloat] restore_start conv=${widget.conversationId}');
    final results = await Future.wait([
      AgentRebateFloatPrefs.instance.readOffset(widget.conversationId),
      AgentRebateFloatPrefs.instance.readExpanded(widget.conversationId,
          defaultValue: widget.defaultExpanded),
    ]);
    if (!mounted) return;
    final media = MediaQuery.of(context);
    final saved = results[0] as Offset?;
    final expanded = results[1] as bool;
    final childSize = expanded
        ? AgentRebateFloatingEntry._expandedSize
        : AgentRebateFloatingEntry._collapsedSize;
    final base = saved ??
        defaultGroupGameFloatOffset(
          screenSize: media.size,
          childSize: childSize,
          bottomInset: media.viewPadding.bottom,
          bottom: widget.defaultBottom,
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
      _preferredOffset = base;
      _offset = next;
      _prefsLoaded = true;
    });
    debugPrint(
        '[AgentRebateFloat] restore_applied conv=${widget.conversationId} '
        'saved=$saved offset=$next expanded=$expanded');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _positionAnimationEnabled = true);
    });
  }

  Offset _defaultOffset(Size screenSize, EdgeInsets padding, Size childSize) {
    return defaultGroupGameFloatOffset(
      screenSize: screenSize,
      childSize: childSize,
      bottomInset: padding.bottom,
      bottom: widget.defaultBottom,
    );
  }

  void _measureChild() {
    final box = _panelKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final size = box.size;
    if ((size.width - _childSize.width).abs() < 0.5 &&
        (size.height - _childSize.height).abs() < 0.5) {
      return;
    }
    final media = MediaQuery.of(context);
    final base =
        _preferredOffset ?? _defaultOffset(media.size, media.viewPadding, size);
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

  void _clampForScreen(Size screenSize, EdgeInsets padding) {
    if (_dragging) return;
    if (_lastScreenSize == screenSize &&
        _lastPadding == padding &&
        _offset != null) {
      return;
    }
    _lastScreenSize = screenSize;
    _lastPadding = padding;
    _offset = snapGroupGameFloatOffsetToHorizontalEdge(
      offset:
          _preferredOffset ?? _defaultOffset(screenSize, padding, _childSize),
      screenSize: screenSize,
      childSize: _childSize,
      viewPadding: padding,
    );
  }

  void _toggleExpanded() {
    if (_dragging || !_prefsLoaded) return;
    final media = MediaQuery.of(context);
    final expanded = !_expanded;
    final size = expanded
        ? AgentRebateFloatingEntry._expandedSize
        : AgentRebateFloatingEntry._collapsedSize;
    setState(() {
      _expanded = expanded;
      _childSize = size;
      _offset = snapGroupGameFloatOffsetToHorizontalEdge(
        offset: _preferredOffset ??
            _defaultOffset(media.size, media.viewPadding, size),
        screenSize: media.size,
        childSize: size,
        viewPadding: media.viewPadding,
      );
    });
    unawaited(AgentRebateFloatPrefs.instance
        .writeExpanded(widget.conversationId, expanded));
  }

  void _onPanUpdate(
    DragUpdateDetails details,
    Size screenSize,
    EdgeInsets padding,
  ) {
    if (!_dragging) return;
    setState(() {
      _offset = clampGroupGameFloatOffset(
        offset: (_offset ?? _defaultOffset(screenSize, padding, _childSize)) +
            details.delta,
        screenSize: screenSize,
        childSize: _childSize,
        viewPadding: padding,
      );
    });
  }

  void _finishDrag(Size screenSize, EdgeInsets padding) {
    if (!_dragging) return;
    final current = _offset;
    if (current == null) return;
    final snapped = snapGroupGameFloatOffsetToHorizontalEdge(
      offset: current,
      screenSize: screenSize,
      childSize: _childSize,
      viewPadding: padding,
    );
    setState(() {
      _dragging = false;
      _offset = snapped;
      _preferredOffset = snapped;
    });
    unawaited(AgentRebateFloatPrefs.instance
        .writeOffset(widget.conversationId, snapped));
  }

  @override
  Widget build(BuildContext context) {
    // Do not paint at the fallback bottom position while disk state is still
    // loading. The first visible frame is therefore already at the persisted
    // position and cannot animate upward from the bottom.
    if (!_prefsLoaded) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    _clampForScreen(media.size, media.viewPadding);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measureChild();
    });
    final offset =
        _offset ?? _defaultOffset(media.size, media.viewPadding, _childSize);

    return AnimatedPositioned(
      duration: (_dragging || !_positionAnimationEnabled)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onPanStart: (_) => _dragging = true,
        onPanUpdate: (details) =>
            _onPanUpdate(details, media.size, media.viewPadding),
        onPanEnd: (_) => _finishDrag(media.size, media.viewPadding),
        onPanCancel: () => _finishDrag(media.size, media.viewPadding),
        child: KeyedSubtree(
          key: _panelKey,
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded ? _buildExpanded() : _buildCollapsed(),
          ),
        ),
      ),
    );
  }

  Widget _buildCollapsed() {
    final i18n = AppI18n.of(context);
    final primary = widget.theme.primaryColor ?? const Color(0xFF1677FF);
    return _roundButton(
      tooltip: i18n.t(zhHans: '展开代理功能', zhHant: '展開代理功能', en: 'Show'),
      onTap: _toggleExpanded,
      child: Text(
        i18n.t(zhHans: '显', zhHant: '顯', en: '+'),
        style: TextStyle(
          fontSize: 24,
          color: primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildExpanded() {
    final i18n = AppI18n.of(context);
    final primary = widget.theme.primaryColor ?? const Color(0xFF1677FF);
    final sangong = widget.variant == AgentRebateFloatingVariant.sangong;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _roundButton(
          tooltip: i18n.t(zhHans: '查下级', zhHant: '查下級', en: 'Downline'),
          onTap: widget.onOpenDescendants,
          child: Text(
            i18n.t(zhHans: '查', zhHant: '查', en: 'Q'),
            style: TextStyle(
              fontSize: 24,
              color: primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(
            zhHans: sangong ? '团队反水' : '当前反水',
            zhHant: sangong ? '團隊反水' : '目前反水',
            en: sangong ? 'Team Rebate' : 'Rebate',
          ),
          onTap: widget.onOpenRebate,
          child: Text(
            sangong
                ? i18n.t(zhHans: '团', zhHant: '團', en: 'T')
                : i18n.t(zhHans: '反', zhHant: '反', en: 'R'),
            style: TextStyle(
              fontSize: 24,
              color: primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: sangong
              ? i18n.t(
                  zhHans: '个人反水',
                  zhHant: '個人反水',
                  en: 'Personal Rebate',
                )
              : i18n.t(
                  zhHans: '历史记录',
                  zhHant: '歷史記錄',
                  en: 'History',
                ),
          onTap: widget.onOpenHistory,
          child: Text(
            sangong
                ? i18n.t(zhHans: '个', zhHant: '個', en: 'P')
                : i18n.t(zhHans: '历', zhHant: '歷', en: 'H'),
            style: TextStyle(
              fontSize: 24,
              color: primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 10),
        _roundButton(
          tooltip: i18n.t(zhHans: '收起', zhHant: '收起', en: 'Collapse'),
          onTap: _toggleExpanded,
          child: Text(
            i18n.t(zhHans: '隐', zhHant: '隱', en: '−'),
            style: TextStyle(
              fontSize: 24,
              color: primary,
              fontWeight: FontWeight.w600,
            ),
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
          onTap: _dragging ? null : onTap,
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
