import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/photo_browser_hero.dart';

void main() {
  for (final slideType in SlideType.values) {
    for (final dragged in [false, true]) {
      testWidgets(
          'return flight keeps fades and drag correction / $slideType dragged=$dragged',
          (tester) async {
        final animation = AnimationController(vsync: tester, value: 1);
        final shuttle = ValueNotifier<Widget>(const SizedBox.shrink());
        addTearDown(animation.dispose);
        addTearDown(shuttle.dispose);
        final slideKey = GlobalKey<ExtendedImageSlidePageState>();
        final fromKey = GlobalKey();
        final toKey = GlobalKey();
        final flightKey = GlobalKey();
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: Stack(children: [
          SizedBox(
              width: 200,
              height: 300,
              child: ExtendedImageSlidePage(
                key: slideKey,
                slideType: slideType,
                slideScaleHandler: (_, {ExtendedImageSlidePageState? state}) =>
                    .8,
                child: HeroWidget(
                  key: fromKey,
                  tag: 'picture',
                  slidePagekey: slideKey,
                  slideType: slideType,
                  child: const SizedBox.expand(key: ValueKey('full-picture')),
                ),
              )),
          Hero(
              key: toKey,
              tag: 'destination',
              child: const SizedBox(
                key: ValueKey('thumbnail'),
                width: 100,
                height: 80,
              )),
          Center(
              child: SizedBox(
                  width: 200,
                  height: 300,
                  child: ValueListenableBuilder<Widget>(
                    key: flightKey,
                    valueListenable: shuttle,
                    builder: (_, child, __) => child,
                  ))),
        ]))));
        if (dragged) {
          slideKey.currentState!.slide(const Offset(30, 70));
          await tester.pump();
        }
        final from = tester.element(find.descendant(
            of: find.byKey(fromKey), matching: find.byType(Hero)));
        final hero = from.widget as Hero;
        hero.createRectTween!(const Rect.fromLTWH(0, 0, 100, 80),
            const Rect.fromLTWH(0, 0, 200, 300));
        shuttle.value = hero.flightShuttleBuilder!(from, animation,
            HeroFlightDirection.pop, from, toKey.currentContext!);
        await tester.pump();
        final picture = find.descendant(
            of: find.byKey(flightKey),
            matching: find.byKey(const ValueKey('full-picture')));
        final thumbnail = find.descendant(
            of: find.byKey(flightKey),
            matching: find.byKey(const ValueKey('thumbnail')));
        final frame = tester.renderObject<RenderBox>(find.byKey(flightKey));
        final content = tester.renderObject<RenderBox>(picture);
        var layoutBuilds = 0;
        debugOnRebuildDirtyWidget = (element, _) {
          if (element.widget is UnconstrainedBox) layoutBuilds++;
        };
        addTearDown(() => debugOnRebuildDirtyWidget = null);
        for (final value in [.75, .5, .25, 0.0]) {
          animation.value = value;
          await tester.pump();
          expect(_opacity(tester, picture), closeTo(value, .000001));
          expect(_opacity(tester, thumbnail), closeTo(1 - value, .000001));
          expect(tester.getSize(thumbnail), const Size(100, 80));
          final corrected = dragged && slideType == SlideType.onlyImage;
          final scale = corrected ? 1 - .2 * value : 1.0;
          final offset = corrected ? const Offset(30, 70) * value : Offset.zero;
          final center = const Size(200, 300).center(Offset.zero);
          final expected = offset + center * (1 - scale);
          final actual = MatrixUtils.transformPoint(
              content.getTransformTo(frame), Offset.zero);
          expect(actual.dx, closeTo(expected.dx, .000001));
          expect(actual.dy, closeTo(expected.dy, .000001));
          final bottomRight = MatrixUtils.transformPoint(
              content.getTransformTo(frame), const Offset(200, 300));
          expect(bottomRight.dx - actual.dx, closeTo(200 * scale, .000001));
          expect(bottomRight.dy - actual.dy, closeTo(300 * scale, .000001));
        }
        expect(layoutBuilds, 0,
            reason: 'The return flight should reuse its thumbnail layout');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

double _opacity(WidgetTester tester, Finder child) {
  final widget = tester.widget(find
      .ancestor(
          of: child,
          matching: find
              .byWidgetPredicate((w) => w is Opacity || w is FadeTransition))
      .first);
  return widget is Opacity
      ? widget.opacity
      : (widget as FadeTransition).opacity.value;
}
