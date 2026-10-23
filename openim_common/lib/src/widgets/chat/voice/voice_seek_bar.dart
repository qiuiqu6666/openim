import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/localization.dart';

/// Message playback waveform. Only horizontal gestures claim the scrubber;
/// vertical drags and long presses remain available to the conversation.
class VoiceSeekBar extends StatefulWidget {
  const VoiceSeekBar({
    super.key,
    required this.progress,
    required this.levels,
    required this.color,
    required this.playedColor,
    required this.waveHeight,
    this.onSeek,
  });

  final double progress;
  final List<double> levels;
  final Color color;
  final Color playedColor;
  final double waveHeight;
  final ValueChanged<double>? onSeek;

  @override
  State<VoiceSeekBar> createState() => _VoiceSeekBarState();
}

class _VoiceSeekBarState extends State<VoiceSeekBar> {
  double? _drag;
  bool _pointerCancelled = false;
  double get _progress => (_drag ?? widget.progress).clamp(0.0, 1.0);

  @override
  void didUpdateWidget(covariant VoiceSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onSeek == null) _drag = null;
  }

  void _commit(double value) {
    setState(() => _drag = null);
    widget.onSeek?.call(value.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onSeek != null;
    String percent(double value) => '${(value.clamp(0.0, 1.0) * 100).round()}%';
    return Semantics(
      container: true,
      slider: true,
      enabled: enabled,
      label: AppCopy.text('语音播放进度'),
      hint: AppCopy.text('点击或左右拖动调整播放位置'),
      value: percent(_progress),
      increasedValue: enabled ? percent(_progress + .1) : null,
      decreasedValue: enabled ? percent(_progress - .1) : null,
      onIncrease: enabled ? () => _commit(_progress + .1) : null,
      onDecrease: enabled ? () => _commit(_progress - .1) : null,
      child: LayoutBuilder(builder: (context, constraints) {
        double fraction(double x) => constraints.maxWidth > 0
            ? (x / constraints.maxWidth).clamp(0.0, 1.0)
            : 0;
        return Listener(
          onPointerDown: (_) => _pointerCancelled = false,
          onPointerCancel: (_) {
            _pointerCancelled = true;
            setState(() => _drag = null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            // Consume disabled taps too: loading/invalid audio must not fall
            // through to the bubble's playback toggle.
            onTapUp: (event) {
              if (enabled) _commit(fraction(event.localPosition.dx));
            },
            onHorizontalDragStart: enabled
                ? (event) =>
                    setState(() => _drag = fraction(event.localPosition.dx))
                : null,
            onHorizontalDragUpdate: enabled
                ? (event) =>
                    setState(() => _drag = fraction(event.localPosition.dx))
                : null,
            onHorizontalDragEnd: enabled
                ? (_) {
                    if (!_pointerCancelled) _commit(_progress);
                  }
                : null,
            onHorizontalDragCancel: () => setState(() => _drag = null),
            child: SizedBox(
              height: kMinInteractiveDimension,
              child: Center(
                child: CustomPaint(
                  size: Size(constraints.maxWidth, widget.waveHeight),
                  painter: VoiceSeekPainter(
                    levels: widget.levels,
                    color: widget.color,
                    playedColor: widget.playedColor,
                    progress: _progress,
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class VoiceSeekPainter extends CustomPainter {
  const VoiceSeekPainter(
      {required this.levels,
      required this.color,
      required this.playedColor,
      required this.progress});
  final List<double> levels;
  final Color color;
  final Color playedColor;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    // A neutral dotted baseline remains seekable before extraction completes.
    final count = levels.isEmpty ? 16 : levels.length;
    final step = size.width / count;
    final paint = Paint()
      ..strokeWidth = math.min(size.height / 9, step * .4)
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      paint.color = (i + .5) / count <= progress ? playedColor : color;
      final level = levels.isEmpty || !levels[i].isFinite
          ? 0.0
          : levels[i].clamp(0.0, 1.0);
      final height = math.max(0.0, size.height * level - paint.strokeWidth);
      final x = step * (i + .5);
      canvas.drawLine(Offset(x, (size.height - height) / 2),
          Offset(x, (size.height + height) / 2), paint);
    }
    paint.color = progress > 0 ? playedColor : color;
    final x = (size.width * progress)
        .clamp(paint.strokeWidth / 2, size.width - paint.strokeWidth / 2);
    canvas.drawLine(Offset(x, paint.strokeWidth / 2),
        Offset(x, size.height - paint.strokeWidth / 2), paint);
  }

  @override
  bool shouldRepaint(covariant VoiceSeekPainter old) =>
      old.levels != levels ||
      old.color != color ||
      old.playedColor != playedColor ||
      old.progress != progress;
}
