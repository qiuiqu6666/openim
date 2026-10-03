import 'dart:math' as math;

import 'package:flutter_screenutil/flutter_screenutil.dart';

/// 99chat's Wallet is authored against a 750 × 1624 design canvas.
///
/// OpenIM initializes ScreenUtil with a different global design size.  These
/// Wallet-only extensions derive scale from the physical logical screen size
/// instead of ScreenUtil's host design size, preserving 99chat coordinates
/// without mutating the rest of the app.
const double wallet99DesignWidth = 750.0;
const double wallet99DesignHeight = 1624.0;

extension Wallet99ScaleNum on num {
  double get _wallet99WidthScale =>
      ScreenUtil().screenWidth / wallet99DesignWidth;

  double get _wallet99HeightScale =>
      ScreenUtil().screenHeight / wallet99DesignHeight;

  double get w99 => toDouble() * _wallet99WidthScale;

  double get h99 => toDouble() * _wallet99HeightScale;

  double get sp99 =>
      toDouble() * math.min(_wallet99WidthScale, _wallet99HeightScale);

  double get r99 => sp99;
}
