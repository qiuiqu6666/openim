// Edge handle / agent controls adapted from 99chat lottery_chat_entry.dart
// and agent_rebate_floating_entry.dart (Apache-2.0).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/group_feature_context.dart';
import '../data/mark_six_controller.dart';
import '../data/mark_six_repository.dart';
import '../mark_six_module.dart';
import 'mark_six_drawer.dart';
import 'mark_six_style.dart';

typedef MarkSixHostBuilder = Widget Function(
    BuildContext context, Widget entry, Widget overlay);

/// Overlay must be placed in the bounded chat-body Stack. It paints no full-size
/// gesture detector; only the 40×56 handle and 58px agent controls intercept taps.
class MarkSixFeatureHost extends StatefulWidget {
  const MarkSixFeatureHost(
      {super.key, required this.featureContext, required this.builder});
  final GroupFeatureContext featureContext;
  final MarkSixHostBuilder builder;
  @override
  State<MarkSixFeatureHost> createState() => _MarkSixFeatureHostState();
}

class _MarkSixFeatureHostState extends State<MarkSixFeatureHost> {
  late MarkSixController _controller;
  double _verticalPosition = .3;
  bool _drawerOpen = false;
  VoidCallback? _dismissDrawer;
  String _contextKey(GroupFeatureContext c) => jsonEncode([
        c.groupID,
        c.currentUserID,
        c.gameType.name,
        c.features.revision,
        c.capabilities.version,
        c.features.markSix.raw,
        c.features.markSix.enabled,
        c.features.markSix.drawHistoryEntry,
        c.features.markSix.agentEntry,
        c.features.markSix.rebateHistoryEntry,
        c.features.markSix.machineCode,
        c.features.markSix.gameID,
        c.capabilities.markSix.machineCode,
        c.capabilities.markSix.gameID,
        c.capabilities.markSix.canOpenAgent,
        c.capabilities.markSix.canViewRebateHistory,
      ]);
  @override
  void initState() {
    super.initState();
    _controller = MarkSixController(MarkSixRepository(widget.featureContext));
  }

  @override
  void didUpdateWidget(covariant MarkSixFeatureHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_contextKey(oldWidget.featureContext) !=
            _contextKey(widget.featureContext) ||
        !oldWidget.featureContext.sessionCurrent()) {
      final retired = _controller;
      final dismiss = _dismissDrawer;
      retired.repository.close();
      _controller = MarkSixController(MarkSixRepository(widget.featureContext));
      _dismissDrawer = null;
      _drawerOpen = false;
      // Routes may still be listening to the old controller until they unmount.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dismiss?.call();
        retired.dispose();
      });
    }
  }

  @override
  void dispose() {
    final dismiss = _dismissDrawer;
    if (dismiss != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => dismiss());
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.featureContext;
    final feature = c.features.markSix;
    final cap = c.capabilities.markSix;
    final enabled = c.sessionCurrent() && feature.enabled;
    final draw = c.showMarkSixDrawHistory &&
        (c.gameType == GroupGameType.markSix ||
            _controller.repository.machineCode.isNotEmpty);
    final agent = enabled &&
        c.capabilitiesCurrent() &&
        feature.agentEntry &&
        cap.canOpenAgent;
    final history = enabled &&
        c.capabilitiesCurrent() &&
        feature.rebateHistoryEntry &&
        cap.canViewRebateHistory;
    final overlay = !draw && !agent && !history
        ? const SizedBox.shrink()
        : Positioned.fill(child: LayoutBuilder(builder: (context, constraints) {
            if (!constraints.hasBoundedHeight || !constraints.hasBoundedWidth) {
              return const SizedBox.shrink();
            }
            const height = 56.0;
            final travel = math.max(0.0, constraints.maxHeight - height);
            final top = (constraints.maxHeight * _verticalPosition - height / 2)
                .clamp(0.0, travel);
            final style = MarkSixStyle.of(context);
            return Stack(children: [
              if (draw)
                Positioned(
                    right: 0,
                    top: top,
                    child: GestureDetector(
                        key: const ValueKey('lottery-edge-handle'),
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: (details) {
                          if (travel <= 0) return;
                          setState(() => _verticalPosition =
                              ((top + details.delta.dy).clamp(0.0, travel) +
                                      height / 2) /
                                  constraints.maxHeight);
                        },
                        onTap: () async {
                          if (_drawerOpen || !_controller.current) return;
                          final openingController = _controller;
                          _drawerOpen = true;
                          final box = context.findRenderObject() as RenderBox?;
                          try {
                            await showMarkSixDrawer(context, openingController,
                                anchorY: box
                                    ?.localToGlobal(Offset(0, top + height / 2))
                                    .dy, onDismissChanged: (dismiss) {
                              if (mounted &&
                                  identical(openingController, _controller)) {
                                _dismissDrawer = dismiss;
                              }
                            });
                          } finally {
                            if (mounted &&
                                identical(openingController, _controller)) {
                              _drawerOpen = false;
                              _dismissDrawer = null;
                            }
                          }
                        },
                        child: Semantics(
                            label: '点击查看开奖记录',
                            button: true,
                            child: SizedBox(
                                width: 40,
                                height: height,
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Container(
                                        width: 28,
                                        height: 48,
                                        decoration: BoxDecoration(
                                            color: style.surface
                                                .withValues(alpha: .8),
                                            borderRadius:
                                                const BorderRadius.horizontal(
                                                    left: Radius.circular(14)),
                                            boxShadow: const [
                                              BoxShadow(
                                                  color: Color(0x10000000),
                                                  blurRadius: 6,
                                                  offset: Offset(-1, 1))
                                            ]),
                                        child: Icon(Icons.chevron_left_rounded,
                                            size: 28,
                                            color: style.secondary))))))),
              if (agent || history)
                _AgentFloatingEntry(
                    key: ValueKey(
                        'mark-six-agent-${c.currentUserID}-${c.groupID}'),
                    featureContext: c,
                    canAgent: agent,
                    canHistory: history,
                    // Opposite initial edge keeps the Sangong floating entry independent.
                    onQuery: () => MarkSixModule.openAgent(context, c),
                    onRebate: () => MarkSixModule.openCurrentRebate(context, c),
                    onHistory: () =>
                        MarkSixModule.openRebateHistory(context, c)),
            ]);
          }));
    return widget.builder(context, const SizedBox.shrink(), overlay);
  }
}

class _AgentFloatingEntry extends StatefulWidget {
  const _AgentFloatingEntry(
      {super.key,
      required this.featureContext,
      required this.canAgent,
      required this.canHistory,
      required this.onQuery,
      required this.onRebate,
      required this.onHistory});
  final GroupFeatureContext featureContext;
  final bool canAgent, canHistory;
  final VoidCallback onQuery, onRebate, onHistory;
  @override
  State<_AgentFloatingEntry> createState() => _AgentFloatingEntryState();
}

class _AgentFloatingEntryState extends State<_AgentFloatingEntry> {
  bool _expanded = false, _loaded = false, _dragging = false, _left = true;
  double _fraction = .6;
  double? _dragX;
  String get _key =>
      'markSix.agentFloat.${widget.featureContext.currentUserID}.${widget.featureContext.groupID}';
  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    final key = _key;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !widget.featureContext.sessionCurrent() || key != _key) {
        return;
      }
      setState(() {
        _expanded = prefs.getBool('$key.expanded') ?? false;
        _left = prefs.getBool('$key.left') ?? true;
        _fraction = (prefs.getDouble('$key.y') ?? .6).clamp(0.0, 1.0);
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    final key = _key, expanded = _expanded, left = _left, fraction = _fraction;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted || !widget.featureContext.sessionCurrent() || key != _key) {
        return;
      }
      await prefs.setBool('$key.expanded', expanded);
      await prefs.setBool('$key.left', left);
      await prefs.setDouble('$key.y', fraction);
    } catch (_) {
      /* Position persistence is optional; business actions stay usable. */
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    unawaited(_save());
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || !widget.featureContext.sessionCurrent()) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
        child: LayoutBuilder(builder: (context, constraints) {
      const width = 58.0;
      final count = (widget.canAgent ? 2 : 0) + (widget.canHistory ? 1 : 0) + 1;
      final height = _expanded ? count * width + (count - 1) * 10 : width;
      final visibleHeight = math.min(height, constraints.maxHeight);
      final maxY = math.max(0.0, constraints.maxHeight - visibleHeight);
      final maxX = math.max(0.0, constraints.maxWidth - width);
      final x =
          (_dragX ?? (_left ? math.min(12.0, maxX) : math.max(0.0, maxX - 12)))
              .clamp(0.0, maxX);
      final y = _fraction * maxY;
      return Stack(children: [
        AnimatedPositioned(
            duration:
                _dragging ? Duration.zero : const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: x,
            top: y,
            child: GestureDetector(
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (details) => setState(() {
                      _dragX = (x + details.delta.dx).clamp(0.0, maxX);
                      _fraction = maxY == 0
                          ? 0
                          : ((y + details.delta.dy).clamp(0.0, maxY) / maxY);
                    }),
                onPanEnd: (_) {
                  setState(() {
                    _left = x + width / 2 < constraints.maxWidth / 2;
                    _dragX = null;
                    _dragging = false;
                  });
                  unawaited(_save());
                },
                onPanCancel: () => setState(() {
                      _dragX = null;
                      _dragging = false;
                    }),
                child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: SizedBox(
                        width: width,
                        height: visibleHeight,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: !_expanded
                                    ? [_button(context, '显', '展开代理功能', _toggle)]
                                    : [
                                        if (widget.canAgent) ...[
                                          _button(context, '查', '查下级',
                                              widget.onQuery),
                                          const SizedBox(height: 10),
                                          _button(context, '反', '当前反水',
                                              widget.onRebate),
                                          const SizedBox(height: 10)
                                        ],
                                        if (widget.canHistory) ...[
                                          _button(context, '历', '历史记录',
                                              widget.onHistory),
                                          const SizedBox(height: 10)
                                        ],
                                        _button(context, '隐', '收起', _toggle),
                                      ]))))))
      ]);
    }));
  }

  Widget _button(
      BuildContext context, String text, String tooltip, VoidCallback action) {
    final style = MarkSixStyle.of(context);
    return Tooltip(
        message: tooltip,
        child: Material(
            color: style.surface,
            shape: const CircleBorder(),
            elevation: _dragging ? 10 : 6,
            shadowColor: style.dark ? Colors.black87 : Colors.black26,
            child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _dragging
                    ? null
                    : () {
                        if (widget.featureContext.sessionCurrent()) action();
                      },
                child: SizedBox.square(
                    dimension: 58,
                    child: Center(
                        child: Text(text,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: style.primary)))))));
  }
}
