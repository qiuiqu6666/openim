import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// The bundled 99chat launch artwork, shared by both app themes.
/// Covers the entire viewport so its system-bar treatment matches native launch.
class SplashArtwork extends StatelessWidget {
  const SplashArtwork({super.key});

  static const asset = 'lib/pages/splash/assets/splash_99chat.webp';

  @override
  Widget build(BuildContext context) => AppSystemBars(
        background: AppTokens.accent,
        child: ColoredBox(
          color: AppTokens.accent,
          child: SizedBox.expand(
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              gaplessPlayback: true,
              semanticLabel: '99CHAT',
            ),
          ),
        ),
      );
}
