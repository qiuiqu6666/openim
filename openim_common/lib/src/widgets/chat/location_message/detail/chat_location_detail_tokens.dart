import 'package:flutter/material.dart';
import '../../../../res/app_tokens.dart';

abstract final class ChatLocationDetailTokens {
  static const controlSize = 48.0;
  static const cardRadius = 28.0;
  static const buttonHeight = 52.0;
  static const titleSize = 18.0;
  static const addressSize = 14.0;
  static const maxCardWidth = 520.0;
  static const surfaceOpacity = .28;
  static const darkSurfaceOpacity = .66;
  static const blueSurfaceOpacity = .76;
  static const edgeOpacity = .5;
  static const edgeWidth = .8;
  static const pressedScale = .96;
  static const pressDuration = Duration(milliseconds: 160);
  static final routeTint = Color.lerp(accent, AppTokens.textPrimaryLight, .25)!;
  static const accent = AppTokens.accent;
}
