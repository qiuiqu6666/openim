import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

/// Ledger float values from 99chat d7c3c65's user profile ledger entry.
abstract final class SangongProfileLedgerTokens {
  static const size = Size(58, 58);
  static const fontSize = 24.0;
  static const fontWeight = FontWeight.w600;
  static const elevation = 6.0;
  static const dragElevation = 10.0;
  static const overlayElevation = 24.0;
  static const snapDuration = Duration(milliseconds: 220);
  static const snapCurve = Curves.easeOutCubic;
  static const fullScreenWidthTolerance = 16.0;
  static const fullScreenHeightTolerance = 120.0;
  static const restoreTolerance = 2.0;

  static Color surface({required bool dark}) =>
      dark ? const Color(0xFF2A2A2E) : AppTokens.surfaceLight;
  static Color shadow({required bool dark}) =>
      dark ? const Color(0xDD000000) : const Color(0x42000000);
  static const accent = AppTokens.accent;
}
