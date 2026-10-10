import 'package:flutter/material.dart';

/// Geometry and artwork colors from 99chat's dedicated image update dialog.
class PlatformUpdateTokens {
  PlatformUpdateTokens._();
  static const artwork = 'assets/images/renew.webp';
  static const radius = 20.0;
  static const minWidth = 280.0, maxWidth = 420.0, widthFraction = .88;
  static const maxHeightFraction = .7;
  static const titleSize = 18.0, bodySize = 14.0;
  static const closeSize = 36.0, closeIconSize = 20.0;
  static const barrier = Color(0x73000000);
  static const darkTint = Color(0xFF6B778C);
  static const shadow = Color(0xFF000000);
  static const darkGradient = [
    Color(0x00121720),
    Color(0x99121720),
    Color(0xF2121720),
  ];
  static const transition = Duration(milliseconds: 240);
}
