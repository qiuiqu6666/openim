import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'qr_scanner_labels.dart';

import 'qr_scanner_layout.dart';

export 'qr_scanner_layout.dart';

class QrScannerOverlay extends StatelessWidget {
  const QrScannerOverlay({
    super.key,
    required this.layout,
    required this.animation,
    required this.onBack,
    required this.onAlbum,
    required this.onFlash,
    required this.onMyQr,
    required this.flashOn,
    this.keyPrefix = 'qr',
    this.showMyQr = true,
  });

  final QrScannerLayout layout;
  final Animation<double> animation;
  final VoidCallback onBack;
  final VoidCallback? onAlbum, onFlash, onMyQr;
  final bool flashOn;
  final String keyPrefix;
  final bool showMyQr;

  @override
  Widget build(BuildContext context) {
    final labels = QrScannerLabels.of(context);
    final fontFamily = Theme.of(context).textTheme.bodyMedium?.fontFamily;
    final flashLabel = flashOn ? labels.flashOff : labels.flashOn;
    final flashColor = onFlash == null
        ? QrScannerTokens.foreground
            .withValues(alpha: QrScannerTokens.disabledOpacity)
        : QrScannerTokens.foreground;
    return Stack(fit: StackFit.expand, children: [
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _ScannerMaskPainter(layout.scanWindow),
          ),
        ),
      ),
      Positioned(
        top: layout.headerTop,
        left: layout.headerLeft,
        right: layout.headerRight,
        height: layout.headerHeight,
        child: Stack(alignment: Alignment.center, children: [
          Positioned(
            left: AppTokens.s2,
            top: 0,
            height: QrScannerTokens.toolbarHeight,
            child: SizedBox(
              width: QrScannerTokens.toolbarHeight,
              child: IconButton(
                key: ValueKey('$keyPrefix-back'),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: onBack,
                color: QrScannerTokens.accent,
                iconSize: QrScannerTokens.backIconSize,
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              ),
            ),
          ),
          if (layout.titleBelowActions)
            Positioned(
                top: QrScannerTokens.toolbarHeight + AppTokens.s2,
                left: AppTokens.s5,
                right: AppTokens.s5,
                child: _title(labels.title))
          else
            _title(labels.title),
          Positioned(
            right: AppTokens.s3,
            top: 0,
            height: QrScannerTokens.toolbarHeight,
            child: TextButton(
              key: ValueKey('$keyPrefix-album'),
              onPressed: onAlbum,
              style: TextButton.styleFrom(
                  foregroundColor: QrScannerTokens.foreground,
                  textStyle: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: QrScannerTokens.albumFontSize,
                      fontWeight: FontWeight.w500)),
              child: Text(labels.album),
            ),
          ),
        ]),
      ),
      Positioned(
        left: QrScannerTokens.instructionInset + layout.headerLeft,
        top: layout.instructionTop,
        bottom: layout.instructionBottom,
        width: layout.instructionWidth,
        child: SizedBox(
          key: ValueKey('$keyPrefix-instruction'),
          child: layout.compact || layout.compactControls
              ? ClipRect(
                  child: SingleChildScrollView(child: _instruction(context)))
              : _instruction(context),
        ),
      ),
      Positioned.fromRect(
        rect: layout.scanWindow,
        child: IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: animation,
              builder: (_, __) => CustomPaint(
                key: ValueKey('$keyPrefix-frame'),
                painter: _ScannerFramePainter(animation.value),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: layout.flashTop,
        left: layout.compact ? layout.scanWindow.right + AppTokens.s5 : 0,
        right: layout.headerRight,
        child: Center(
          child: TextButton(
            key: ValueKey('$keyPrefix-flash'),
            onPressed: onFlash,
            style: TextButton.styleFrom(
                foregroundColor: flashColor,
                disabledForegroundColor: flashColor,
                padding: const EdgeInsets.all(AppTokens.s3)),
            child: Semantics(
              toggled: flashOn,
              child: layout.compactControls
                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          flashOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          size: QrScannerTokens.flashIconSize,
                          color: flashOn
                              ? QrScannerTokens.flashActive
                              : flashColor),
                      const SizedBox(width: AppTokens.s3),
                      Flexible(
                          child: Text(flashLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: flashColor.withValues(
                                      alpha: onFlash == null
                                          ? QrScannerTokens.disabledOpacity
                                          : QrScannerTokens.secondaryOpacity),
                                  fontSize: QrScannerTokens.flashFontSize,
                                  fontWeight: FontWeight.w500))),
                    ])
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          flashOn
                              ? Icons.flash_on_rounded
                              : Icons.flash_off_rounded,
                          size: QrScannerTokens.flashIconSize,
                          color: flashOn
                              ? QrScannerTokens.flashActive
                              : flashColor),
                      const SizedBox(height: AppTokens.s3),
                      Text(flashLabel,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: flashColor.withValues(
                                  alpha: onFlash == null
                                      ? QrScannerTokens.disabledOpacity
                                      : QrScannerTokens.secondaryOpacity),
                              fontSize: QrScannerTokens.flashFontSize,
                              fontWeight: FontWeight.w500)),
                    ]),
            ),
          ),
        ),
      ),
      if (showMyQr)
        Positioned(
          left: layout.headerLeft,
          right: layout.compact
              ? MediaQuery.sizeOf(context).width - layout.scanWindow.left
              : layout.headerRight,
          bottom: layout.linkBottom,
          child: Center(
            child: TextButton(
              key: ValueKey('$keyPrefix-my-code'),
              onPressed: onMyQr,
              style: TextButton.styleFrom(
                  foregroundColor: QrScannerTokens.link,
                  disabledForegroundColor: QrScannerTokens.link
                      .withValues(alpha: QrScannerTokens.disabledOpacity),
                  minimumSize: const Size(0, QrScannerTokens.actionMinHeight),
                  padding: EdgeInsets.symmetric(
                      horizontal: layout.compactControls ? 0 : AppTokens.s6,
                      vertical:
                          layout.compactControls ? AppTokens.s2 : AppTokens.s3),
                  textStyle: TextStyle(
                      fontFamily: fontFamily,
                      fontSize: QrScannerTokens.linkFontSize,
                      height: QrScannerTokens.actionLineHeight,
                      fontWeight: FontWeight.w500)),
              child: Text(labels.myQr, textAlign: TextAlign.center),
            ),
          ),
        ),
    ]);
  }

  Widget _instruction(BuildContext context) => Text(
        QrScannerLabels.of(context).instruction,
        style: QrScannerLayout.instructionStyle,
      );

  Widget _title(String title) => Text(title,
      key: ValueKey('$keyPrefix-title'),
      textAlign: TextAlign.center,
      style: const TextStyle(
          color: QrScannerTokens.foreground,
          fontSize: QrScannerTokens.titleFontSize,
          fontWeight: FontWeight.w700));
}

class _ScannerMaskPainter extends CustomPainter {
  const _ScannerMaskPainter(this.window);
  final Rect window;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(RRect.fromRectAndRadius(
          window, const Radius.circular(QrScannerTokens.frameRadius)));
    canvas.drawPath(
        path,
        Paint()
          ..color = QrScannerTokens.background
              .withValues(alpha: QrScannerTokens.maskOpacity));
  }

  @override
  bool shouldRepaint(_ScannerMaskPainter oldDelegate) =>
      window != oldDelegate.window;
}

class _ScannerFramePainter extends CustomPainter {
  const _ScannerFramePainter(this.progress);
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const color = QrScannerTokens.accent;
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect.deflate(QrScannerTokens.cornerStroke / 2),
        Paint()
          ..color = color.withValues(alpha: .88)
          ..strokeWidth = QrScannerTokens.thinStroke
          ..style = PaintingStyle.stroke);
    const inset = QrScannerTokens.scanInset;
    final scanY = QrScannerTokens.scanLineInset +
        (size.height - QrScannerTokens.scanLineInset * 2) * progress;
    final gridBottom = math.max(inset, scanY);
    final gridPaint = Paint()
      ..color = color.withValues(alpha: .28)
      ..strokeWidth = QrScannerTokens.gridStroke;
    canvas.save();
    canvas
        .clipRect(Rect.fromLTRB(inset, inset, size.width - inset, gridBottom));
    for (var column = 1; column < QrScannerTokens.gridColumns; column++) {
      final x = size.width * column / QrScannerTokens.gridColumns;
      canvas.drawLine(Offset(x, inset), Offset(x, gridBottom), gridPaint);
    }
    for (var y = gridBottom; y > inset; y -= QrScannerTokens.gridRowSpacing) {
      final distance = math.min(gridBottom - y, 84.0);
      canvas.drawLine(
          Offset(inset, y),
          Offset(size.width - inset, y),
          Paint()
            ..color = color.withValues(alpha: .14 + (84 - distance) / 84 * .18)
            ..strokeWidth = QrScannerTokens.gridStroke);
    }
    canvas.restore();
    final glow = Rect.fromLTWH(inset, scanY - QrScannerTokens.glowHeight / 2,
        size.width - inset * 2, QrScannerTokens.glowHeight);
    canvas.save();
    canvas.clipRect(rect.deflate(inset));
    canvas.drawRect(
        glow,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0),
              color.withValues(alpha: .26),
              color.withValues(alpha: 0)
            ],
          ).createShader(glow));
    canvas.restore();
    canvas.drawLine(
        Offset(inset, scanY),
        Offset(size.width - inset, scanY),
        Paint()
          ..color = color.withValues(alpha: .98)
          ..strokeWidth = QrScannerTokens.scanLineStroke
          ..strokeCap = StrokeCap.round);
    final corner = Paint()
      ..color = color
      ..strokeWidth = QrScannerTokens.cornerStroke
      ..strokeCap = StrokeCap.square;
    final length = size.width * QrScannerTokens.cornerFraction;
    for (final origin in [
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height)
    ]) {
      final dx = origin.dx == 0 ? length : -length;
      final dy = origin.dy == 0 ? length : -length;
      canvas.drawLine(origin, origin.translate(dx, 0), corner);
      canvas.drawLine(origin, origin.translate(0, dy), corner);
    }
    final notch = size.height * .86;
    final halfNotch = math.min(22.0, size.height * .08);
    for (final x in [0.0, size.width]) {
      canvas.drawLine(
          Offset(x, notch - halfNotch), Offset(x, notch + halfNotch), corner);
    }
  }

  @override
  bool shouldRepaint(_ScannerFramePainter oldDelegate) =>
      progress != oldDelegate.progress;
}
