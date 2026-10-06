import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:zxing2/qrcode.dart';

/// Compare the actual QR painter with an independently encoded endpoint value.
/// This verifies rendered modules, including correction level and style, rather
/// than merely inspecting a widget's address property.
Future<void> expectDepositAddressQr(
    WidgetTester tester, Finder qr, String address) async {
  final paint = tester.widget<CustomPaint>(find.descendant(
      of: qr,
      matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is QrPainter)));
  final actual = paint.painter! as QrPainter;
  final expected = QrPainter(
      data: address,
      version: QrVersions.auto,
      errorCorrectionLevel: actual.errorCorrectionLevel,
      gapless: actual.gapless,
      eyeStyle: actual.eyeStyle,
      dataModuleStyle: actual.dataModuleStyle);
  await tester.runAsync(() async {
    Future<List<int>> pixels(QrPainter painter) async {
      final picture = painter.toPicture(220);
      final image = await picture.toImage(220, 220);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return data!.buffer.asUint8List().toList(growable: false);
      } finally {
        image.dispose();
        picture.dispose();
      }
    }

    final rendered = await pixels(actual);
    final reference = await pixels(expected);
    expect(rendered, isNotEmpty);
    expect(listEquals(rendered, reference), isTrue,
        reason: 'Rendered QR must encode the authenticated deposit address');
  });
}

/// Decode the same PNG bytes that will be written as the preview artifact.
String decodeDepositPngQr(Uint8List bytes, Rect rect, {double pixelRatio = 2}) {
  final sourceImage = img.decodePng(bytes)!;
  final crop = img.copyCrop(sourceImage,
      x: (rect.left * pixelRatio).round(),
      y: (rect.top * pixelRatio).round(),
      width: (rect.width * pixelRatio).round(),
      height: (rect.height * pixelRatio).round());
  final pixels = Int32List(crop.width * crop.height);
  var index = 0;
  for (final pixel in crop) {
    pixels[index++] =
        pixel.r.toInt() << 16 | pixel.g.toInt() << 8 | pixel.b.toInt();
  }
  return QRCodeReader()
      .decode(BinaryBitmap(
          HybridBinarizer(RGBLuminanceSource(crop.width, crop.height, pixels))))
      .text;
}

/// Decode a crop from the painted production page, including the center logo.
Future<String> decodeDepositRenderedQr(
    WidgetTester tester, GlobalKey boundaryKey, Finder qr) async {
  final render =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final origin = tester.getTopLeft(find.byKey(boundaryKey));
  final rect = tester.getRect(qr).shift(-origin);
  const ratio = 3.0;
  return (await tester.runAsync(() async {
    final full = await render.toImage(pixelRatio: ratio);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
        full,
        Rect.fromLTWH(rect.left * ratio, rect.top * ratio, rect.width * ratio,
            rect.height * ratio),
        Rect.fromLTWH(0, 0, rect.width * ratio, rect.height * ratio),
        Paint());
    final picture = recorder.endRecording();
    final crop = await picture.toImage(
        (rect.width * ratio).round(), (rect.height * ratio).round());
    try {
      final bytes = await crop.toByteData(format: ui.ImageByteFormat.rawRgba);
      final data = bytes!.buffer.asUint8List();
      final pixels = Int32List(crop.width * crop.height);
      for (var index = 0; index < pixels.length; index++) {
        final offset = index * 4;
        pixels[index] =
            data[offset] << 16 | data[offset + 1] << 8 | data[offset + 2];
      }
      final source = RGBLuminanceSource(crop.width, crop.height, pixels);
      return QRCodeReader().decode(BinaryBitmap(HybridBinarizer(source))).text;
    } finally {
      crop.dispose();
      picture.dispose();
      full.dispose();
    }
  }))!;
}
