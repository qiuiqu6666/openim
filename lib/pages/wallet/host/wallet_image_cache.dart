import 'package:flutter/widgets.dart';

class ImageMemCacheSize {
  ImageMemCacheSize._();

  static int forLogicalSize(
    double logicalSize,
    BuildContext context, {
    int min = 1,
    int max = 2048,
  }) {
    if (!logicalSize.isFinite || logicalSize <= 0) return max;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return (logicalSize * dpr).round().clamp(min, max);
  }
}
