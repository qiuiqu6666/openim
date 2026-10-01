import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/media_preview_glass.dart';

void main() {
  testWidgets(
      'glass transmits live background colors without a navigation fill',
      (tester) async {
    final background = ValueNotifier<Color>(Colors.green);
    addTearDown(background.dispose);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: boundaryKey,
          child: SizedBox.square(
            dimension: 100,
            child: Stack(fit: StackFit.expand, children: [
              ValueListenableBuilder<Color>(
                valueListenable: background,
                builder: (_, color, __) => ColoredBox(color: color),
              ),
              const Center(
                child: MediaPreviewGlass(
                  borderRadius: BorderRadius.all(Radius.circular(24)),
                  child: SizedBox.square(dimension: 48),
                ),
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    Future<List<int>> sample() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      final offset = (50 * 100 + 50) * 4;
      return List.generate(3, (i) => data!.getUint8(offset + i));
    }

    final green = await tester.runAsync(sample);
    expect(green![1], greaterThan(green[0]));
    expect(green[1], greaterThan(green[2]));
    background.value = Colors.red;
    await tester.pumpAndSettle();
    final red = await tester.runAsync(sample);
    expect(red![0], greaterThan(red[1]));
    expect(red[0], greaterThan(red[2]));
    expect(red, isNot(green));

    // A visible surface over black, while white content stays legible over
    // bright media. Dark colored media must still retain its color through it.
    background.value = Colors.black;
    await tester.pumpAndSettle();
    final black = (await tester.runAsync(sample))!;
    expect(black[0], inInclusiveRange(12, 40));
    background.value = Colors.white;
    await tester.pumpAndSettle();
    final bright = (await tester.runAsync(sample))!;
    final luminance =
        Color.fromARGB(255, bright[0], bright[1], bright[2]).computeLuminance();
    expect(1.05 / (luminance + .05), greaterThanOrEqualTo(4.5));
    background.value = const Color(0xFF102850);
    await tester.pumpAndSettle();
    final dark = (await tester.runAsync(sample))!;
    expect(dark[2], greaterThan(dark[1]));
    expect(dark[1], greaterThan(dark[0]));
    expect(dark[2], greaterThan(black[2]));
  });

  testWidgets('press feedback preserves taps and honors reduced motion',
      (tester) async {
    var taps = 0;
    for (final reduced in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: Center(
            child: MediaPreviewGlass(
              interactive: true,
              borderRadius: BorderRadius.circular(24),
              child: IconButton(
                icon: const Icon(Icons.download),
                onPressed: () => taps++,
              ),
            ),
          ),
        ),
      ));
      final gesture = await tester
          .startGesture(tester.getCenter(find.byIcon(Icons.download)));
      await tester.pump();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
          reduced ? 1 : .96);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    }
    expect(taps, 2);
  });
}
