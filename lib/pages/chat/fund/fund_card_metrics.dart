import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Port of 99chat's ChatWalletCardMetrics. OpenIM's ScreenUtil design is
/// 375x812, so mobile design values are converted from the reference's 750x1624.
abstract final class FundCardMetrics {
  FundCardMetrics._();

  static const double designMaxWidth = 340;
  static const double designMinWidth = 180;
  static const double mobileCardMaxWidth = 290;
  static const double mobileCardMinWidth = 168;
  static const double designMinCardHeight = 156;
  static const double designFooterBlockHeight = 40;
  static const double designIconSize = 68;
  static const double webWidthScale = .82;
  static const double webHeightScale = .72;
  static const double webVerticalScale = .68;
  static const double webCardTextScale = .78;
  static const double desktopLayoutScale = .75;
  static const double desktopCardMaxWidth = 264;
  static const double desktopIconSizePx = 40;
  static const double desktopTitleFontSize = 14;
  static const double desktopSubtitleFontSize = 12;
  static const double desktopFooterFontSize = 11;
  static const double desktopFooterPadV = 6;
  static const double minMobileScale = .5;
  static const double maxMobileScale = 1.5;
  static const double desktopLogicalScale = .5;

  static const double cardRadius = 14;
  static const double packetIconRadius = 8;
  static const double transferIconRadius = 12;
  static const double transferIconPaddingRatio = .18;
  static const double tailOverhang = 9;
  static const double tailWidth = 14;
  static const double tailHeight = 24;
  static const double tailTop = 22;
  static const double titleSizeMobile = 15;
  static const double subtitleSizeMobile = 22;
  static const double packetAmountSize = 32;
  static const double packetSummaryGap = 8;
  static const double packetSummaryLineHeight = 1.1;
  static const double packetAmountLetterSpacing = .4;
  static const double packetFooterSize = 20;
  static const double transferFooterSize = 18;
  static const double lineHeight = 1.25;
  static const double shadowOpacity = .18;
  static const double shadowBlur = 10;
  static const double shadowOffset = 3;
  static const double packetFooterOpacity = .92;
  static const double openedIconOpacity = .72;

  static bool get isWeb => kIsWeb;
  static bool get useDesktopChatCard =>
      !isWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS);

  static double get maxWidth => isWeb
      ? designMaxWidth * webWidthScale
      : useDesktopChatCard
          ? desktopCardMaxWidth
          : mobileCardMaxWidth;

  static double get minWidth => isWeb
      ? designMinWidth * webWidthScale
      : useDesktopChatCard
          ? 200
          : mobileCardMinWidth;

  static double get minCardHeight => isWeb
      ? designMinCardHeight * webHeightScale * webVerticalScale
      : useDesktopChatCard
          ? 0
          : h(designMinCardHeight);

  static double get footerBlockHeight => isWeb
      ? designFooterBlockHeight * webHeightScale * webVerticalScale
      : useDesktopChatCard
          ? 0
          : h(designFooterBlockHeight);

  static double get minBodyHeight {
    final value = minCardHeight - footerBlockHeight;
    return value > 0 ? value : 0;
  }

  static double desktopMaxWidthForChat() => maxWidth;

  static double clampCardWidth(double parentMax) {
    if (!parentMax.isFinite || parentMax <= 0) return maxWidth;
    return math.min(maxWidth, math.max(minWidth, parentMax));
  }

  @visibleForTesting
  static double boundedMobileScale(double rawScale) =>
      !rawScale.isFinite || rawScale <= 0
          ? 1
          : rawScale.clamp(minMobileScale, maxMobileScale).toDouble();

  static double _safeMobileScaled(num value, double Function(num value) scale) {
    final designValue = value.toDouble();
    if (designValue == 0) return 0;
    try {
      final referenceScale = scale(value) / designValue / 2;
      return designValue * boundedMobileScale(referenceScale);
    } catch (_) {
      return designValue / 2;
    }
  }

  static double w(num value) => isWeb
      ? value.toDouble() * webWidthScale
      : useDesktopChatCard
          ? value.toDouble() * desktopLayoutScale
          : _safeMobileScaled(value, (input) => input.w);

  static double h(num value) => isWeb
      ? value.toDouble() * webHeightScale * webVerticalScale
      : useDesktopChatCard
          ? value.toDouble() * desktopLayoutScale
          : _safeMobileScaled(value, (input) => input.h);

  static double sp(num value) => isWeb
      ? value.toDouble() * webWidthScale
      : useDesktopChatCard
          ? value.toDouble() * desktopLogicalScale
          : _safeMobileScaled(value, (input) => input.sp);

  static double r(num value) => isWeb
      ? value.toDouble() * webWidthScale
      : useDesktopChatCard
          ? value.toDouble() * desktopLayoutScale
          : _safeMobileScaled(value, (input) => input.r);

  static double iconSize([num design = designIconSize]) => isWeb
      ? design.toDouble() * webHeightScale * .78
      : useDesktopChatCard
          ? desktopIconSizePx
          : w(design);

  static double footerSp([num design = 18]) => isWeb
      ? design.toDouble() * webHeightScale * .92
      : useDesktopChatCard
          ? desktopFooterFontSize
          : sp(design);

  static double titleFontSize({required double mobile}) =>
      useDesktopChatCard ? desktopTitleFontSize : mobile;

  static double subtitleFontSize({required double mobile}) =>
      useDesktopChatCard ? desktopSubtitleFontSize : mobile;

  static EdgeInsets get bodyPadding => useDesktopChatCard
      ? const EdgeInsets.fromLTRB(12, 10, 12, 8)
      : EdgeInsets.fromLTRB(w(16), h(12), w(16), h(8));

  static EdgeInsets get footerPadding => useDesktopChatCard
      ? const EdgeInsets.symmetric(horizontal: 12, vertical: desktopFooterPadV)
      : EdgeInsets.symmetric(horizontal: w(16), vertical: h(8));

  static double get leadingTextGap => useDesktopChatCard ? 10 : w(12);

  static double lineGap({required double mobile}) =>
      useDesktopChatCard ? 4 : mobile;

  static double cardSp(num value) => isWeb
      ? value.toDouble() * webWidthScale * webCardTextScale
      : useDesktopChatCard
          ? value.toDouble() * desktopLogicalScale
          : _safeMobileScaled(value, (input) => input.sp);
}
