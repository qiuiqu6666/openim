import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'qr_scanner_labels.dart';

/// Matches the reference on phones while keeping controls clear in landscape
/// and when the instruction wraps at a larger system text size.
class QrScannerLayout {
  QrScannerLayout(BuildContext context, Size size) {
    final padding = MediaQuery.paddingOf(context);
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final instruction = TextPainter(
      text: TextSpan(
        text: QrScannerLabels.of(context).instruction,
        style: instructionStyle.copyWith(fontFamily: fontFamily),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    compact = size.width > size.height;
    headerTop = padding.top;
    headerLeft = padding.left;
    headerRight = padding.right;
    final usableWidth = size.width - padding.horizontal;
    final direction = Directionality.of(context);
    final labels = QrScannerLabels.of(context);
    // Keep the reference's centered toolbar when it fits. Larger translated
    // labels move the full title below the action row without shrinking text.
    final title = TextPainter(
      text: TextSpan(
          text: labels.title,
          style: DefaultTextStyle.of(context).style.copyWith(
              fontSize: QrScannerTokens.titleFontSize,
              fontWeight: FontWeight.w700)),
      textDirection: direction,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: math.max(1, usableWidth - AppTokens.s5 * 2));
    final album = TextPainter(
      text: TextSpan(
          text: labels.album,
          style: TextStyle(
              fontFamily: fontFamily,
              fontSize: QrScannerTokens.albumFontSize,
              fontWeight: FontWeight.w500)),
      textDirection: direction,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final defaults = const TextButton(onPressed: null, child: SizedBox.shrink())
        .defaultStyleOf(context);
    final buttonTheme = TextButtonTheme.of(context).style;
    final albumPadding = (buttonTheme?.padding ?? defaults.padding)
            ?.resolve(const <WidgetState>{})?.resolve(direction) ??
        EdgeInsets.zero;
    final albumMinimum = (buttonTheme?.minimumSize ?? defaults.minimumSize)
            ?.resolve(const <WidgetState>{}) ??
        Size.zero;
    final albumWidth =
        math.max(albumMinimum.width, album.width + albumPadding.horizontal);
    final titleLeft = (usableWidth - title.width) / 2;
    final titleRight = (usableWidth + title.width) / 2;
    titleBelowActions = titleLeft <
            AppTokens.s2 + QrScannerTokens.toolbarHeight + AppTokens.s2 ||
        titleRight > usableWidth - AppTokens.s3 - albumWidth - AppTokens.s2;
    headerHeight = QrScannerTokens.toolbarHeight +
        (titleBelowActions ? title.height + AppTokens.s2 * 2 : 0);
    title.dispose();
    album.dispose();
    final headerBottom = headerTop + headerHeight;
    if (compact) {
      compactControls = false;
      final side = math.max(
          48.0,
          math.min(size.height - headerBottom - padding.bottom - AppTokens.s8,
              usableWidth * QrScannerTokens.frameHeightFraction));
      scanWindow = Rect.fromLTWH(padding.left + (usableWidth - side) / 2,
          headerBottom + AppTokens.s5, side, side);
      instructionTop = scanWindow.top;
      instructionWidth = math.max(
          48.0,
          scanWindow.left -
              padding.left -
              QrScannerTokens.instructionInset * 2);
      flashTop = scanWindow.center.dy - QrScannerTokens.flashIconSize;
      linkBottom = padding.bottom + AppTokens.s5;
      final linkText = TextPainter(
        text: TextSpan(
            text: QrScannerLabels.of(context).myQr,
            style: TextStyle(
                fontFamily: fontFamily,
                fontSize: QrScannerTokens.linkFontSize,
                height: QrScannerTokens.actionLineHeight,
                fontWeight: FontWeight.w500)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(
          maxWidth:
              math.max(1.0, scanWindow.left - padding.left - AppTokens.s6 * 2));
      instructionBottom = linkBottom +
          math.max(
              QrScannerTokens.actionMinHeight, linkText.height + AppTokens.s5) +
          AppTokens.s5;
      linkText.dispose();
    } else {
      instructionWidth = usableWidth - QrScannerTokens.instructionInset * 2;
      instruction.layout(maxWidth: instructionWidth);
      final referenceInstructionTop = math.max(
          size.height * QrScannerTokens.instructionTopFraction,
          headerBottom + AppTokens.s5);
      final referenceLinkBottom = math.max(
          size.height * QrScannerTokens.linkBottomFraction,
          padding.bottom + AppTokens.s4);
      final scale = MediaQuery.textScalerOf(context);
      final linkHeight = math.max(QrScannerTokens.actionMinHeight,
          scale.scale(QrScannerTokens.linkFontSize) * 1.4 + AppTokens.s5);
      final flashHeight = QrScannerTokens.flashIconSize +
          AppTokens.s3 +
          scale.scale(QrScannerTokens.flashFontSize) * 1.4 +
          AppTokens.s5;
      final latestFlashTop = size.height -
          referenceLinkBottom -
          linkHeight -
          AppTokens.s5 -
          flashHeight;
      final top = math.max(size.height * QrScannerTokens.frameTopFraction,
          referenceInstructionTop + instruction.height + AppTokens.s7);
      final side = math.max(
          48.0,
          math.min(
              math.min(
                  usableWidth * QrScannerTokens.frameWidthFraction,
                  math.min(size.height * QrScannerTokens.frameHeightFraction,
                      QrScannerTokens.frameMaxSide)),
              latestFlashTop - AppTokens.s7 - top));
      final referenceWindow = Rect.fromLTWH(
          padding.left + (usableWidth - side) / 2, top, side, side);
      final referenceFlashTop = math.min(
          referenceWindow.bottom + QrScannerTokens.flashGap, latestFlashTop);

      double textHeight(String text, TextStyle style, double width) {
        final painter = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: scale)
          ..layout(maxWidth: math.max(1, width));
        final height = painter.height;
        painter.dispose();
        return height;
      }

      final flashStyle = (Theme.of(context).textTheme.labelLarge ??
              DefaultTextStyle.of(context).style)
          .copyWith(
              fontFamily: fontFamily,
              fontSize: QrScannerTokens.flashFontSize,
              fontWeight: FontWeight.w500);
      final linkStyle = TextStyle(
          fontFamily: fontFamily,
          fontSize: QrScannerTokens.linkFontSize,
          height: QrScannerTokens.actionLineHeight,
          fontWeight: FontWeight.w500);
      double flashTextHeight(double width) => math.max(
          textHeight(labels.flashOn, flashStyle, width),
          textHeight(labels.flashOff, flashStyle, width));
      final actualFlashHeight = QrScannerTokens.flashIconSize +
          AppTokens.s3 +
          flashTextHeight(usableWidth - AppTokens.s3 * 2) +
          AppTokens.s3 * 2;
      final actualLinkHeight = math.max(
          QrScannerTokens.actionMinHeight,
          textHeight(labels.myQr, linkStyle, usableWidth - AppTokens.s6 * 2) +
              AppTokens.s3 * 2);
      compactControls = latestFlashTop - AppTokens.s7 - top <
              QrScannerTokens.actionMinHeight ||
          referenceWindow.bottom + AppTokens.s3 > referenceFlashTop ||
          referenceFlashTop + actualFlashHeight + AppTokens.s3 >
              size.height - referenceLinkBottom - actualLinkHeight;
      if (compactControls) {
        // Prioritize the real scan window and controls. Only decorative gaps
        // and instruction viewport shrink; system text remains fully scaled.
        linkBottom = padding.bottom + AppTokens.s3;
        final linkHeight = math.max(QrScannerTokens.actionMinHeight,
            textHeight(labels.myQr, linkStyle, usableWidth) + AppTokens.s2 * 2);
        final flashHeight = math.max(
            QrScannerTokens.actionMinHeight,
            math.max(
                    QrScannerTokens.flashIconSize,
                    flashTextHeight(usableWidth -
                        AppTokens.s3 * 3 -
                        QrScannerTokens.flashIconSize)) +
                AppTokens.s3 * 2);
        flashTop =
            size.height - linkBottom - linkHeight - AppTokens.s3 - flashHeight;
        final frameBottom = flashTop - AppTokens.s3;
        instructionTop = headerBottom + AppTokens.s3;
        final available = frameBottom - instructionTop - AppTokens.s5;
        final instructionLine = math.min(
            instruction.height,
            scale.scale(QrScannerTokens.instructionFontSize) *
                QrScannerTokens.instructionLineHeight);
        final side = math.max(
            QrScannerTokens.actionMinHeight,
            math.min(
                math.min(usableWidth * QrScannerTokens.frameWidthFraction,
                    size.height * QrScannerTokens.frameHeightFraction),
                available - instructionLine));
        final frameTop = frameBottom - side;
        scanWindow = Rect.fromLTWH(
            padding.left + (usableWidth - side) / 2, frameTop, side, side);
        final viewportHeight = math.max(
            0.0,
            math.min(
                instruction.height, frameTop - AppTokens.s5 - instructionTop));
        instructionBottom = size.height - instructionTop - viewportHeight;
      } else {
        instructionTop = referenceInstructionTop;
        linkBottom = referenceLinkBottom;
        scanWindow = referenceWindow;
        flashTop = referenceFlashTop;
      }
    }
    instruction.dispose();
  }

  static const instructionStyle = TextStyle(
    color: QrScannerTokens.foreground,
    fontSize: QrScannerTokens.instructionFontSize,
    height: QrScannerTokens.instructionLineHeight,
    fontWeight: FontWeight.w400,
  );

  late final Rect scanWindow;
  late final bool compact;
  late final bool compactControls;
  late final bool titleBelowActions;
  late final double headerHeight;
  late final double headerTop, headerLeft, headerRight;
  late final double instructionTop, instructionWidth, flashTop, linkBottom;
  double? instructionBottom;
}
