import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'wallet_home_test_support.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
        'pressed wallet controls stay inside their surfaces in $brightness',
        (tester) async {
      final boundary = GlobalKey();
      final controller = await loadedHomeController();
      await pumpWalletHome(tester,
          controller: controller,
          brightness: brightness,
          boundaryKey: boundary);
      await tester.pumpAndSettle();
      await settleWalletHomeImages(tester);
      for (final key in [
        'wallet-action-receive',
        'wallet-action-transfer',
        'wallet-action-swap',
        'wallet-action-record',
        'wallet-action-overview',
        'wallet-toggle-balance',
        'wallet-assets-filter',
        'wallet-assets-toggle',
        'wallet-asset-99',
        'wallet-asset-USDT',
      ]) {
        await tester.ensureVisible(walletHomeKey(key));
        await tester.pumpAndSettle();
        await _expectPressedPixelsClipped(tester,
            boundaryKey: boundary, target: walletHomeKey(key));
      }
      expect(tester.takeException(), isNull);
    });
  }
}

Future<void> _expectPressedPixelsClipped(
  WidgetTester tester, {
  required GlobalKey boundaryKey,
  required Finder target,
}) async {
  final targetWidget = tester.widget(target);
  final ink = targetWidget is InkResponse
      ? target
      : find
          .descendant(
              of: target,
              matching:
                  find.byWidgetPredicate((widget) => widget is InkResponse))
          .first;
  final materialFinder =
      find.ancestor(of: ink, matching: find.byType(Material)).first;
  final material = tester.widget<Material>(materialFinder);
  final shape = material.shape;
  final radius = shape is RoundedRectangleBorder
      ? shape.borderRadius.resolve(TextDirection.ltr)
      : material.borderRadius?.resolve(TextDirection.ltr) ?? BorderRadius.zero;
  final boundary =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final origin = boundary.localToGlobal(Offset.zero);
  final rect = tester.getRect(materialFinder).shift(-origin);
  final allowed = radius.toRRect(rect).inflate(1);
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
  final gesture = await tester.startGesture(tester.getCenter(ink));
  try {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 100));
    final after = await snapshot();
    var inside = 0;
    var outside = 0;
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
          inside++;
        } else {
          outside++;
        }
      }
    }
    expect(inside, greaterThan(0),
        reason: '$target: missing visible press feedback');
    expect(outside, 0,
        reason: '$target: pressed ink escaped its rounded surface');
  } finally {
    // Cancel avoids mounting secondary routes while testing paint boundaries.
    await gesture.cancel();
    await tester.pumpAndSettle();
  }
}
