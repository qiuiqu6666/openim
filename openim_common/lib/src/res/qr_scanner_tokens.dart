import 'package:flutter/material.dart';

import 'app_tokens.dart';

/// Immersive QR camera geometry and colors from 99chat's scanner page.
/// Camera controls stay on a dark surface in both application themes.
class QrScannerTokens {
  QrScannerTokens._();

  static const background = Color(0xFF000000);
  static const foreground = AppTokens.onAccent;
  static const accent = AppTokens.accent;
  static const flashActive = Color(0xFF3D7BFF);
  static const link = Color(0xFF2F80FF);
  static const maskOpacity = .34;
  static const disabledOpacity = .38;
  static const secondaryOpacity = .78;
  static const toolbarHeight = kToolbarHeight;
  static const backIconSize = 25.0;
  static const titleFontSize = 18.0;
  static const albumFontSize = 17.0;
  static const instructionFontSize = 18.0;
  static const instructionLineHeight = 1.35;
  static const instructionInset = 26.0;
  static const frameWidthFraction = .72;
  static const frameHeightFraction = .36;
  static const frameTopFraction = .34;
  static const instructionTopFraction = .22;
  static const frameMaxSide = 420.0;
  static const frameRadius = 14.0;
  static const flashGap = 78.0;
  static const flashIconSize = 34.0;
  static const flashFontSize = 14.0;
  static const linkFontSize = 16.0;
  static const actionLineHeight = 1.4;
  static const linkBottomFraction = .07;
  static const actionMinHeight = 48.0;
  static const scanDuration = Duration(milliseconds: 1900);
  static const cameraStartTimeout = Duration(seconds: 4);
  static const thinStroke = 2.0;
  static const cornerStroke = 6.0;
  static const cornerFraction = .14;
  static const gridColumns = 24;
  static const gridRowSpacing = 14.0;
  static const gridStroke = .75;
  static const scanInset = 8.0;
  static const scanLineInset = 10.0;
  static const glowHeight = 56.0;
  static const scanLineStroke = 2.2;
}
