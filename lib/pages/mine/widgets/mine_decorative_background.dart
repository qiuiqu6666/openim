import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

class MineDecorativeBackground extends StatelessWidget {
  const MineDecorativeBackground({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: dark ? Alignment.topLeft : Alignment.topCenter,
            end: dark ? Alignment.bottomRight : Alignment.bottomCenter,
            colors: dark
                ? AppTokens.decorativeGradientDark
                : AppTokens.decorativeGradientLight,
            stops: dark ? AppTokens.decorativeGradientDarkStops : null,
          ),
        ),
      );
}

class MineTopSparkles extends StatelessWidget {
  const MineTopSparkles({super.key, required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            return Stack(
              children: [
                _sparkle(width * 0.19, null, height * 0.30, width * 0.022,
                    dark ? 0.42 : 0.58),
                _sparkle(width * 0.33, null, height * 0.52, width * 0.034,
                    dark ? 0.48 : 0.62),
                _sparkle(null, width * 0.18, height * 0.36, width * 0.024,
                    dark ? 0.38 : 0.52),
                _sparkle(null, width * 0.34, height * 0.70, width * 0.014,
                    dark ? 0.32 : 0.42),
              ],
            );
          },
        ),
      );

  Widget _sparkle(
    double? left,
    double? right,
    double top,
    double size,
    double opacity,
  ) =>
      Positioned(
        left: left,
        right: right,
        top: top,
        child: _MineDecorativeSparkle(
          size: size,
          opacity: opacity,
          dark: dark,
        ),
      );
}

class _MineDecorativeSparkle extends StatelessWidget {
  const _MineDecorativeSparkle({
    required this.size,
    required this.opacity,
    required this.dark,
  });

  final double size;
  final double opacity;
  final bool dark;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: opacity,
        child: Transform.rotate(
          angle: 0.78,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? AppTokens.decorativeSparkle.withValues(alpha: 0.55)
                  : AppTokens.onAccent,
              borderRadius: BorderRadius.circular(size * 0.18),
              boxShadow: defaultTargetPlatform == TargetPlatform.android
                  ? const <BoxShadow>[]
                  : [
                      BoxShadow(
                        color: AppTokens.decorativeSparkle
                            .withValues(alpha: dark ? 0.28 : 0.20),
                        blurRadius: size,
                      ),
                    ],
            ),
            child: SizedBox(width: size, height: size),
          ),
        ),
      );
}
