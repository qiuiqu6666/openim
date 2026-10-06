import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Main chat sticker sizing from 99chat's resolveStickerMessageSize path.
abstract final class StickerBubbleLayout {
  static const radius = 6.0;
  static const placeholderIconFactor = 0.3;
  static const longImageAspectRatio = 0.45;
  static const longImageWidth = 92.0;
  static const longImageHeight = 190.0;
  static const metadataInset = 4.0;
  static const metadataHorizontalPadding = 4.0;
  static const metadataVerticalPadding = 2.0;
  static const metadataMinHeight = 32.0;
  static const metadataBackgroundOpacity = 0.55;
  static const rowGap = 12.0;
  static const rowInset = 16.0;

  static bool get usesDesktopLimits =>
      !kIsWeb &&
      [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]
          .contains(defaultTargetPlatform);

  static ({double width, double height, double factor}) _limits(
      Size screenSize, bool isDesktop) {
    if (isDesktop || screenSize.width >= 600) {
      return (width: 260, height: 230, factor: 0.34);
    }
    if (screenSize.width < 360 || screenSize.height < 700) {
      return (width: 132, height: 150, factor: 0.54);
    }
    if (screenSize.height < 840) {
      return (width: 144, height: 160, factor: 0.54);
    }
    return (width: 156, height: 176, factor: 0.54);
  }

  static bool isValidSize(Size? size) =>
      size != null &&
      size.width.isFinite &&
      size.height.isFinite &&
      size.width > 0 &&
      size.height > 0;

  /// Normal stickers fit proportionally; very tall ones use a readable crop.
  static Size imageSize(
    Size intrinsicSize, {
    Size screenSize = const Size(375, 812),
    double availableWidth = double.infinity,
    double availableHeight = double.infinity,
    bool isDesktop = false,
  }) {
    final limits = _limits(screenSize, isDesktop);
    final rowWidth = availableWidth.isFinite
        ? math.max(0.0, availableWidth)
        : screenSize.width * (isDesktop ? 0.45 : 0.7);
    final widthLimit = math.min(limits.width, rowWidth * limits.factor);
    final heightLimit = math.min(limits.height, math.max(0.0, availableHeight));
    if (!isValidSize(intrinsicSize)) {
      final side = math.min(widthLimit, heightLimit);
      return Size.square(side);
    }
    if (widthLimit <= 0 || heightLimit <= 0) return Size.zero;
    final scale = math.min(
        widthLimit / intrinsicSize.width, heightLimit / intrinsicSize.height);
    final fitted = intrinsicSize * scale;
    final portrait = intrinsicSize.height > intrinsicSize.width;
    if (portrait &&
        (intrinsicSize.aspectRatio < longImageAspectRatio ||
            fitted.height >= heightLimit - 0.5 &&
                fitted.width < longImageWidth)) {
      return Size(math.min(longImageWidth, widthLimit),
          math.min(longImageHeight, heightLimit));
    }
    return fitted;
  }

  static BoxFit imageFit(Size? source, Size display) => isValidSize(source) &&
          display.height > 0 &&
          (display.aspectRatio - source!.aspectRatio).abs() > 0.01
      ? BoxFit.cover
      : BoxFit.contain;

  static Size placeholderSize({
    Size screenSize = const Size(375, 812),
    double availableWidth = double.infinity,
    double availableHeight = double.infinity,
    bool isDesktop = false,
  }) =>
      imageSize(Size.zero,
          screenSize: screenSize,
          availableWidth: availableWidth,
          availableHeight: availableHeight,
          isDesktop: isDesktop);
}
