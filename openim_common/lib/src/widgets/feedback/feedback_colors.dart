import 'package:flutter/material.dart';
import '../../res/app_tokens.dart';

/// Floating feedback keeps a matched dark surface and light foreground in
/// both themes, independently of the page's background and theme transitions.
abstract final class FeedbackColors {
  static const background = Color(0xFF0C1C33);
  static const foreground = AppTokens.onAccent;
}
