import 'package:flutter/material.dart';
import '../../theme/ai_palette.dart';

class AiCanvasBackdrop extends StatelessWidget {
  const AiCanvasBackdrop({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final top = AiPalette.headerBg(dark);
    final mid = AiPalette.canvasBg(dark);
    final bottom =
        dark ? AiPalette.canvasBg(true) : AiPalette.backdropBottomLight;
    final glowA = AiPalette.accent.withValues(alpha: dark ? 0.16 : 0.14);
    final glowB = AiPalette.userBubble.withValues(alpha: dark ? 0.12 : 0.10);
    final sparkle = AiPalette.accent.withValues(alpha: dark ? 0.28 : 0.22);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[top, mid, bottom],
          stops: const <double>[0, 0.42, 1],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: AiMetrics.positionMinus70,
            right: AiMetrics.positionMinus50,
            child: AiGlowOrb(size: AiMetrics.dimension220, color: glowA),
          ),
          Positioned(
            top: AiMetrics.position180,
            left: AiMetrics.positionMinus80,
            child: AiGlowOrb(size: AiMetrics.dimension180, color: glowB),
          ),
          Positioned(
            bottom: AiMetrics.position90,
            right: AiMetrics.positionMinus40,
            child: AiGlowOrb(size: AiMetrics.dimension160, color: glowA),
          ),
          Positioned(
            top: AiMetrics.position72,
            left: AiMetrics.position28,
            child: Icon(Icons.auto_awesome,
                size: AiMetrics.dimension16, color: sparkle),
          ),
          Positioned(
            top: AiMetrics.position128,
            right: AiMetrics.position36,
            child: Icon(Icons.auto_awesome,
                size: AiMetrics.dimension12, color: sparkle),
          ),
          Positioned(
            bottom: AiMetrics.position168,
            left: AiMetrics.position48,
            child:
                Icon(Icons.circle, size: AiMetrics.dimension6, color: sparkle),
          ),
          Positioned(
            bottom: AiMetrics.position220,
            right: AiMetrics.position72,
            child:
                Icon(Icons.circle, size: AiMetrics.dimension5, color: sparkle),
          ),
        ],
      ),
    );
  }
}

class AiGlowOrb extends StatelessWidget {
  const AiGlowOrb({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color,
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
