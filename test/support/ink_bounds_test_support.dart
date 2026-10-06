import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Compare painted pixels, including the parent Material where ink is rendered.
/// Existing shadows are allowed; only new pixels outside the surface fail.
Future<void> expectInkWithinSurface(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
  required Finder target,
  required BorderRadius radius,
  Rect? surfaceRect,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final origin = boundary.localToGlobal(Offset.zero);
  final surface = (surfaceRect ?? tester.getRect(target)).shift(-origin);
  final allowed = radius.toRRect(surface).inflate(1);
  Future<(Uint8List, int, int)> snapshot() async =>
      (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        final result = (bytes!.buffer.asUint8List(), image.width, image.height);
        image.dispose();
        return result;
      }))!;
  final before = await snapshot();
  final gesture = await tester.startGesture(tester.getCenter(target));
  try {
    await tester.pump(const Duration(milliseconds: 200));
    // Tap-down can be deferred while the recognizer resolves its arena.
    await tester.pump(const Duration(milliseconds: 100));
    final after = await snapshot();
    var insideChanges = 0;
    var outsideChanges = 0;
    for (var y = 0; y < before.$3; y++) {
      for (var x = 0; x < before.$2; x++) {
        final offset = (y * before.$2 + x) * 4;
        var changed = false;
        for (var channel = 0; channel < 4; channel++) {
          if ((before.$1[offset + channel] - after.$1[offset + channel]).abs() >
              8) {
            changed = true;
            break;
          }
        }
        if (!changed) continue;
        if (allowed.contains(Offset(x + .5, y + .5))) {
          insideChanges++;
        } else {
          outsideChanges++;
        }
      }
    }
    expect(insideChanges, greaterThan(0),
        reason: 'The pressed state must still provide visible feedback');
    expect(outsideChanges, 0,
        reason: 'Pressed ink must stay inside the visible rounded surface');
  } finally {
    await gesture.up();
    await tester.pumpAndSettle();
  }
}
