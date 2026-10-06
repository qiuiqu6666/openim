// Adapted from 99chat's conversation_peek_overlay.dart layout.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: layout accepts menu counts and the current text scaler, without SDK state.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Percentage geometry within the preview route's SafeArea.
class ConversationPeekLayout {
  ConversationPeekLayout._();

  static const horizontalInsetFactor = .037;
  static const topInsetFactor = .008;
  static const bottomInsetFactor = .016;
  static const previewHeightFactor = .60;
  static const previewMenuGapFactor = .012;
  static const menuWidthFactor = .48;
  static const cardRadiusFactor = .058;
  static const menuItemVerticalPaddingFactor = .012;
  static const menuRowContentHeight = 22.0;
  static const menuLabelFontSize = 15.0;
  static const menuDividerHeight = 1.0;
  static const menuLayoutSlack = 12.0;
  static const minimumPreviewHeight = 120.0;

  static ConversationPeekMetrics resolve({
    required BoxConstraints constraints,
    required double screenWidth,
    required int menuItemCount,
    required int menuDividerCount,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    assert(menuItemCount >= 0 && menuDividerCount >= 0);
    final availableHeight = constraints.maxHeight;
    final horizontalPadding = screenWidth * horizontalInsetFactor;
    final topPadding = availableHeight * topInsetFactor;
    final bottomPadding = availableHeight * bottomInsetFactor;
    final gap = availableHeight * previewMenuGapFactor;
    final usableHeight = availableHeight - topPadding - bottomPadding;
    final menuItemVerticalPadding =
        availableHeight * menuItemVerticalPaddingFactor;
    final scaledRowHeight = math.max(
      menuRowContentHeight,
      textScaler.scale(menuLabelFontSize) *
          menuRowContentHeight /
          menuLabelFontSize,
    );
    final menuNaturalHeight =
        menuItemCount * (menuItemVerticalPadding * 2 + scaledRowHeight) +
            menuDividerCount * menuDividerHeight +
            menuLayoutSlack;
    final maxPreviewHeight =
        math.max(0.0, usableHeight - gap - menuNaturalHeight);
    final previewHeight = maxPreviewHeight <= 0
        ? 0.0
        : (usableHeight * previewHeightFactor)
            .clamp(math.min(minimumPreviewHeight, maxPreviewHeight),
                maxPreviewHeight)
            .toDouble();
    final menuViewportHeight =
        (usableHeight - previewHeight - gap).clamp(0.0, menuNaturalHeight);
    return ConversationPeekMetrics(
      horizontalPadding: horizontalPadding,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
      gap: gap,
      previewHeight: previewHeight,
      menuWidth: screenWidth * menuWidthFactor,
      menuNaturalHeight: menuNaturalHeight,
      menuViewportHeight: menuViewportHeight,
      cardWidth: screenWidth - horizontalPadding * 2,
      cardRadius: screenWidth * cardRadiusFactor,
      menuItemVerticalPadding: menuItemVerticalPadding,
    );
  }
}

class ConversationPeekMetrics {
  const ConversationPeekMetrics({
    required this.horizontalPadding,
    required this.topPadding,
    required this.bottomPadding,
    required this.gap,
    required this.previewHeight,
    required this.menuWidth,
    required this.menuNaturalHeight,
    required this.menuViewportHeight,
    required this.cardWidth,
    required this.cardRadius,
    required this.menuItemVerticalPadding,
  });

  final double horizontalPadding;
  final double topPadding;
  final double bottomPadding;
  final double gap;
  final double previewHeight;
  final double menuWidth;
  final double menuNaturalHeight;
  final double menuViewportHeight;
  final double cardWidth;
  final double cardRadius;
  final double menuItemVerticalPadding;

  bool get menuNeedsScroll => menuNaturalHeight > menuViewportHeight + .5;
}
