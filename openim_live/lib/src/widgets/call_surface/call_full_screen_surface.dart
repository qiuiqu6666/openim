import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Full-screen calls keep an immersive palette in both app themes, matching
/// 99chat's call canvas and the original light/dark button artwork.
class CallSurfaceTokens {
  CallSurfaceTokens._();

  static const background = Color(0xFF2D2D2D);
  static const foreground = AppTokens.onAccent;
  static final secondary = foreground.withValues(alpha: .72);
}

/// Kept inside the full-screen branch so minimized/system PiP calls release
/// their system-bar annotation and let the underlying page own its colors.
class CallFullScreenSurface extends StatelessWidget {
  const CallFullScreenSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSystemBars(
      background: CallSurfaceTokens.background,
      child: Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            brightness: Brightness.dark,
            surface: CallSurfaceTokens.background,
            onSurface: CallSurfaceTokens.foreground,
            onSurfaceVariant: CallSurfaceTokens.secondary,
          ),
          iconTheme:
              theme.iconTheme.copyWith(color: CallSurfaceTokens.foreground),
        ),
        child: Material(color: CallSurfaceTokens.background, child: child),
      ),
    );
  }
}
