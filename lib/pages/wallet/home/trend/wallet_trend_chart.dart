import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

import '../../widgets/wallet_99chat_tokens.dart';
import '../../widgets/wallet_page_colors.dart';
import '../wallet_home_tokens.dart';
import '../../data/wallet_trend_data.dart';
import 'wallet_trend_geometry.dart';
import 'wallet_trend_display_points.dart';

class WalletTrendChart extends StatefulWidget {
  const WalletTrendChart(
      {super.key, required this.data, this.onInspect, this.onInspectEnd});
  final WalletTrendData data;
  final ValueChanged<String?>? onInspect;
  final VoidCallback? onInspectEnd;

  @override
  State<WalletTrendChart> createState() => _WalletTrendChartState();
}

class _WalletTrendChartState extends State<WalletTrendChart> {
  late WalletTrendDisplayPoints _display;
  int? _selected;
  Offset? _touchStart;
  bool _scrubbing = false;

  @override
  void initState() {
    super.initState();
    _display = WalletTrendDisplayPoints(widget.data.points);
  }

  @override
  void didUpdateWidget(WalletTrendChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _display = WalletTrendDisplayPoints(widget.data.points);
      _selected = null;
      _touchStart = null;
      _scrubbing = false;
    }
  }

  void _select(int index) {
    if (_selected == index) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() => _selected = index);
    widget.onInspect?.call(_display.points[index].totalCny);
  }

  void _selectAt(double x, WalletTrendGeometry geometry) {
    _select(geometry.nearest(x));
  }

  void _finish() {
    _touchStart = null;
    _scrubbing = false;
    if (_selected == null) return;
    setState(() => _selected = null);
    widget.onInspectEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = WalletPageColors.of(context);
    final selected = _selected;
    return Padding(
      padding: const EdgeInsets.all(AppTokens.s2),
      child: LayoutBuilder(builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final geometry =
            WalletTrendGeometry(_display.points, size, evenlySpaced: true);
        return Semantics(
          label: '人民币总可用余额趋势，${_display.points.length}个滑动点，按住横向滑动查看余额，松开恢复当前余额',
          value: selected == null ? null : _pointLabel(selected),
          increasedValue: selected == null
              ? null
              : _pointLabel(
                  (selected + 1).clamp(0, _display.points.length - 1)),
          decreasedValue: selected == null
              ? null
              : _pointLabel(
                  (selected - 1).clamp(0, _display.points.length - 1)),
          onIncrease: () => _select(
              ((selected ?? -1) + 1).clamp(0, _display.points.length - 1)),
          onDecrease: () => _select(((selected ?? _display.points.length) - 1)
              .clamp(0, _display.points.length - 1)),
          onDismiss: _finish,
          child: Listener(
            onPointerDown: (event) {
              _touchStart = event.localPosition;
              _selectAt(event.localPosition.dx, geometry);
            },
            onPointerMove: (event) {
              final start = _touchStart;
              if (start != null) {
                final delta = event.localPosition - start;
                // Let vertical page scrolling dismiss the preview.
                if (!_scrubbing &&
                    delta.dy.abs() > kTouchSlop &&
                    delta.dy.abs() > delta.dx.abs()) {
                  _finish();
                } else if (_scrubbing || delta.dx.abs() >= delta.dy.abs()) {
                  // Small adjacent-slot movements must work before the drag
                  // recognizer's touch-slop threshold is reached.
                  _selectAt(event.localPosition.dx, geometry);
                }
              }
            },
            onPointerUp: (_) => _finish(),
            onPointerCancel: (_) => _finish(),
            child: GestureDetector(
              key: const ValueKey('wallet-trend-chart'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                _scrubbing = true;
                _selectAt(details.localPosition.dx, geometry);
              },
              onHorizontalDragUpdate: (details) =>
                  _selectAt(details.localPosition.dx, geometry),
              onHorizontalDragEnd: (_) => _finish(),
              onLongPressStart: (details) {
                _scrubbing = true;
                _selectAt(details.localPosition.dx, geometry);
              },
              onLongPressMoveUpdate: (details) =>
                  _selectAt(details.localPosition.dx, geometry),
              onLongPressEnd: (_) => _finish(),
              child: RepaintBoundary(
                  child: Stack(children: [
                CustomPaint(
                    size: size,
                    painter: _TrendPainter(
                        geometry: geometry,
                        selected: selected,
                        line: WalletHomeTokens.trendAccent,
                        surface: colors.card)),
                if (selected != null)
                  Positioned(
                    left: (geometry.xs[selected] - WalletHomeTokens.divider / 2)
                        .clamp(0.0, size.width - WalletHomeTokens.divider),
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                        child: SizedBox(
                            key: const ValueKey('wallet-trend-cursor'),
                            width: WalletHomeTokens.divider,
                            child: ColoredBox(color: colors.line))),
                  ),
              ])),
            ),
          ),
        );
      }),
    );
  }

  String _pointLabel(int index) {
    final amount = _display.points[index].totalCny;
    return amount == null ? '历史价格暂缺' : '¥$amount';
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(
      {required this.geometry,
      required this.selected,
      required this.line,
      required this.surface});
  final WalletTrendGeometry geometry;
  final int? selected;
  final Color line;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = line
      ..strokeWidth = WalletHomeTokens.progressStroke
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final path in geometry.paths) {
      canvas.drawPath(path, paint);
    }
    // Singleton segments, including the one-record case, remain visible.
    for (var i = 0; i < geometry.offsets.length; i++) {
      final point = geometry.offsets[i];
      if (point != null &&
          (i == 0 || geometry.offsets[i - 1] == null) &&
          (i == geometry.offsets.length - 1 ||
              geometry.offsets[i + 1] == null)) {
        canvas.drawCircle(
            point, WalletHomeTokens.progressStroke, Paint()..color = line);
      }
    }
    final index = selected;
    if (index == null) return;
    final point = geometry.offsets[index];
    if (point != null) {
      canvas.drawCircle(point, AppTokens.s2, Paint()..color = surface);
      canvas.drawCircle(
          point, WalletHomeTokens.progressStroke, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.geometry != geometry ||
      old.selected != selected ||
      old.line != line ||
      old.surface != surface;
}
