import 'package:openim_common/localization.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../data/mark_six_controller.dart';
import 'mark_six_style.dart';

/// The wall clock and countdown are the only second-by-second card content.
class MarkSixClockRow extends StatefulWidget {
  const MarkSixClockRow({super.key, required this.controller});
  final MarkSixController controller;

  @override
  State<MarkSixClockRow> createState() => _MarkSixClockRowState();
}

class _MarkSixClockRowState extends State<MarkSixClockRow>
    with WidgetsBindingObserver {
  final _visibilityKey = UniqueKey();
  Timer? _timer;
  bool _visible = false, _routeActive = false, _foreground = false;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
    _syncTimer();
  }

  @override
  void didUpdateWidget(MarkSixClockRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _syncTimer();
  }

  bool get _active =>
      _visible &&
      _routeActive &&
      _foreground &&
      widget.controller.current &&
      widget.controller.ready;

  void _syncTimer() {
    if (!_active) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_active) {
        _syncTimer();
        return;
      }
      setState(() {});
    });
  }

  void _changed() {
    if (!mounted) return;
    _syncTimer();
    if (_active) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _changed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    VisibilityDetectorController.instance.forget(_visibilityKey);
    super.dispose();
  }

  String get _countdown {
    final round = widget.controller.currentRound;
    if (round == null) return AppCopy.text('期数待更新');
    if (round.status == 'drawn') return AppCopy.text('已开奖');
    if (round.status == 'closed' || round.status == 'drawing')
      return AppCopy.text('正在开奖');
    final stamp = round.raw['closeAt'] ?? round.raw['drawAt'];
    if (stamp is! num)
      return round.status == 'open' ? '投注中' : AppCopy.text('等待开奖');
    final seconds =
        (DateTime.fromMillisecondsSinceEpoch(stamp.toInt(), isUtc: true)
                .difference(widget.controller.now())
                .inSeconds)
            .clamp(0, 86400);
    return '${round.status == 'open' ? AppCopy.text('封盘') : AppCopy.text('开奖')} ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final style = MarkSixStyle.of(context);
    final now = widget.controller.now().add(const Duration(hours: 8));
    String two(int n) => n.toString().padLeft(2, '0');
    return VisibilityDetector(
      key: _visibilityKey,
      onVisibilityChanged: (info) {
        final visible = info.visibleFraction > 0;
        if (!mounted || visible == _visible) return;
        _visible = visible;
        _changed();
      },
      child: Row(children: [
        Expanded(
            child: Text(
                AppCopy.format('当前时间 {#0}-{#1}-{#2} {#3}:{#4}:{#5}', [
                  now.year,
                  two(now.month),
                  two(now.day),
                  two(now.hour),
                  two(now.minute),
                  two(now.second)
                ]),
                style: TextStyle(fontSize: 11, color: style.secondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 4),
        Text(_countdown,
            style: TextStyle(
                fontSize: 11,
                color: widget.controller.currentRound?.status == 'open'
                    ? style.primary
                    : MarkSixStyle.red)),
      ]),
    );
  }
}
