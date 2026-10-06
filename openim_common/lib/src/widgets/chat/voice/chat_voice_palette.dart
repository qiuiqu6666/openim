import 'package:flutter/material.dart';

import '../../../res/app_tokens.dart';
import '../../../res/chat_voice_tokens.dart';

/// Theme-resolved colors shared by idle and active voice presentations.
class ChatVoicePalette {
  ChatVoicePalette.of(BuildContext context)
      : dark = Theme.of(context).brightness == Brightness.dark,
        scheme = Theme.of(context).colorScheme;

  final bool dark;
  final ColorScheme scheme;

  Color get surface => ChatComposerTokens.surface(dark: dark);
  Color get text => AppTokens.textPrimary(dark: dark);
  Color get secondary => scheme.onSurfaceVariant;
  Color get accent => AppTokens.accent;

  /// Keep the brand blue for icons, with a readable derivative for selected text.
  Color get selectedText {
    if (dark) return accent;
    final backgroundLuminance = surface.computeLuminance();
    for (var step = 0; step <= 10; step++) {
      final candidate = Color.lerp(accent, text, step / 10)!;
      final foregroundLuminance = candidate.computeLuminance();
      final contrast = backgroundLuminance >= foregroundLuminance
          ? (backgroundLuminance + .05) / (foregroundLuminance + .05)
          : (foregroundLuminance + .05) / (backgroundLuminance + .05);
      if (contrast >= ChatVoiceTokens.minimumTextContrast) return candidate;
    }
    return text;
  }

  Color get onAccent => AppTokens.onAccent;
  Color get controlSurface => AppTokens.surfaceAlt(dark: dark);
  Color get border => AppTokens.border(dark: dark);
  Color get danger => AppTokens.paymentError(dark: dark);
  Color get scrim => ChatVoiceTokens.scrim.withValues(
      alpha: dark
          ? ChatVoiceTokens.scrimOpacityDark
          : ChatVoiceTokens.scrimOpacityLight);

  Color selectedSurface(Color color) => color.withValues(
      alpha: dark
          ? ChatVoiceTokens.selectionOpacityDark
          : ChatVoiceTokens.selectionOpacityLight);
}
