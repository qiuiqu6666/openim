import '../progress/sector_progress_painter.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../res/app_tokens.dart';

/// A filled sector reports real byte progress, without a looping animation.
class OriginalImageProgress extends StatelessWidget {
  const OriginalImageProgress({super.key, this.event});

  final ImageChunkEvent? event;

  double? get progress {
    final total = event?.expectedTotalBytes;
    if (total == null || total <= 0) return null;
    return (event!.cumulativeBytesLoaded / total).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final value = progress;
    final label = 'mediaViewOriginal'.tr;
    return IgnorePointer(
      child: Semantics(
        label: label,
        value: value == null ? null : '${(value * 100).floor()}%',
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.s3),
          child: SizedBox.square(
            dimension: AppTokens.s8,
            child: CustomPaint(
              painter: SectorProgressPainter(
                progress: value,
                color: AppTokens.textPrimary(dark: true),
              ),
              // Unknown content length must not invent a percentage.
              child: value == null
                  ? Icon(Icons.downloading,
                      color: AppTokens.textPrimary(dark: true),
                      size: AppTokens.s5)
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
