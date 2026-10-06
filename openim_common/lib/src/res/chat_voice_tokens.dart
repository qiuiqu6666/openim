import 'package:flutter/material.dart';

/// Geometry and presentation for the shared mobile voice input panel.
class ChatVoiceTokens {
  ChatVoiceTokens._();

  static const double panelHeight = 248;
  static const double micSize = 80;
  static const double micIconSize = 32;
  static const double sideSize = 56;
  static const double minimumTouchSize = 44;
  static const double sideGap = 24;
  static const double hitOutset = 10;
  static const double mainCenterY = 150;
  static const double horizontalInset = 16;
  static const double headerTop = 20;
  static const double hintTop = 52;
  static const double waveformTop = 64;
  static const double waveformHeight = 32;
  static const double waveformHorizontalInset = 24;
  static const int waveformCount = 24;
  static const double waveformBarWidth = 3;
  static const double waveformMinHeight = 2;
  static const double controlLabelWidth = 88;
  static const double controlLabelGap = 12;
  static const double titleFontSize = 16;
  static const double hintFontSize = 14;
  static const double durationFontSize = 15;
  static const double textLineHeight = 1.25;
  static const double controlFontSize = 14;
  static const double controlLineHeight = 1.2;
  static const double iconSize = 24;
  static const double spinnerRadius = 12;
  static const double headerSpinnerRadius = 8;
  static const double headerGap = 8;
  static const double durationGap = 12;
  static const double borderWidth = 1;
  static const double largeTextScale = 1.5;
  static const double minimumTextContrast = 4.5;
  static const double scrimOpacityLight = .16;
  static const double scrimOpacityDark = .24;
  static const double selectionOpacityLight = .1;
  static const double selectionOpacityDark = .18;
  static const Color scrim = Color(0xFF000000);
  static const Duration stateAnimation = Duration(milliseconds: 120);
  static const Duration panelAnimationDuration = Duration(milliseconds: 200);
}
