import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../res/chat_voice_tokens.dart';

/// Static history of real normalized amplitude samples, oldest on the left.
/// Empty or silent input remains a baseline; no animation invents samples.
class ChatVoiceWaveform extends StatelessWidget {
  const ChatVoiceWaveform({
    super.key,
    required this.levels,
    required this.color,
    this.height = ChatVoiceTokens.waveformHeight,
  });

  final List<double> levels;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '实时音量波形',
        image: true,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: CustomPaint(
            painter: _VoiceWaveformPainter(
                levels: List<double>.unmodifiable(levels), color: color),
          ),
        ),
      );
}

class _VoiceWaveformPainter extends CustomPainter {
  const _VoiceWaveformPainter({required this.levels, required this.color});

  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const count = ChatVoiceTokens.waveformCount;
    final visible =
        levels.length > count ? levels.sublist(levels.length - count) : levels;
    final emptyCount = count - visible.length;
    final step = size.width / count;
    final width = math.min(ChatVoiceTokens.waveformBarWidth, step);
    final paint = Paint()..color = color;
    for (var index = 0; index < count; index++) {
      final sample = index < emptyCount ? 0.0 : visible[index - emptyCount];
      final level = sample.isFinite ? sample.clamp(0.0, 1.0).toDouble() : 0.0;
      final barHeight =
          math.max(ChatVoiceTokens.waveformMinHeight, size.height * level);
      final rect = Rect.fromLTWH(step * (index + .5) - width / 2,
          (size.height - barHeight) / 2, width, barHeight);
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(width / 2)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VoiceWaveformPainter oldDelegate) =>
      color != oldDelegate.color || !listEquals(levels, oldDelegate.levels);
}
