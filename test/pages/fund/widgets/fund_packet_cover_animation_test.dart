import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/widgets/fund_packet_cover.dart';

void main() {
  testWidgets('backdrop keeps its blur subtree while fading out',
      (tester) async {
    final split = AnimationController(vsync: tester);
    addTearDown(split.dispose);
    await tester.pumpWidget(MaterialApp(
        home: FundPacketCoverOverlay(
      cover: const SizedBox.expand(),
      split: split,
      splitting: false,
      loadingIndicator: const SizedBox.shrink(),
      onClose: () {},
      onViewDetails: null,
      viewDetailsLabel: 'Details',
      closeLabel: 'Close',
    )));
    final blur = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    for (final value in [0.0, .25, .5, .75, 1.0]) {
      split.value = value;
      await tester.pump();
      final fade = tester.widget<FadeTransition>(find
          .ancestor(
            of: find.byKey(const ValueKey('fund-detail-scrim')),
            matching: find.byType(FadeTransition),
          )
          .first);
      expect(fade.opacity.value,
          closeTo(1 - Curves.easeInCubic.transform(value), .000001));
      expect(tester.widget<BackdropFilter>(find.byType(BackdropFilter)),
          same(blur));
    }
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('split preserves travel and fades / $brightness',
        (tester) async {
      final spin = AnimationController(vsync: tester);
      final split = AnimationController(vsync: tester);
      addTearDown(spin.dispose);
      addTearDown(split.dispose);
      await tester.pumpWidget(_host(spin, split, brightness: brightness));
      final art = find.byKey(const ValueKey('fund-reference-cover-art'));
      final origin = tester.getTopLeft(art);
      expect(art, findsOneWidget);
      for (final value in [.01, .25, .5, .75, 1.0]) {
        split.value = value;
        await tester.pump();
        final progress = Curves.easeInCubic.transform(value);
        expect(art, findsNWidgets(2));
        for (var i = 0; i < 2; i++) {
          expect(
              tester.getTopLeft(art.at(i)).dy,
              closeTo(
                  origin.dy + (i == 0 ? -1 : 1) * 400 * 1.08 * progress, .001));
          final fade = find.ancestor(
              of: art.at(i),
              matching: find.byWidgetPredicate(
                  (w) => w is Opacity || w is FadeTransition));
          final widget = tester.widget(fade.first);
          final opacity = widget is Opacity
              ? widget.opacity
              : (widget as FadeTransition).opacity.value;
          expect(opacity, closeTo(1 - progress * .18, .000001));
        }
      }
      split.value = 0;
      await tester.pump();
      expect(art, findsOneWidget);
      expect(tester.getTopLeft(art), origin);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('coin keeps the same perspective, rotation and pulse',
      (tester) async {
    final spin = AnimationController(vsync: tester);
    final split = AnimationController(vsync: tester);
    addTearDown(spin.dispose);
    addTearDown(split.dispose);
    await tester.pumpWidget(_host(spin, split));
    final outer = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('fund-detail-open-animation')));
    final coin = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('fund-detail-open')));
    for (final value in [0.0, .13, .25, .5, .8, 1.0]) {
      spin.value = value;
      await tester.pump();
      final center = outer.size.center(Offset.zero);
      final scale = 1 + math.sin(value * math.pi) * .035;
      final expected = Matrix4.translationValues(center.dx, center.dy, 0)
        ..multiply(Matrix4.identity()
          ..setEntry(3, 2, .0012)
          ..rotateY(Curves.easeInOutCubic.transform(value) * math.pi * 3))
        ..multiply(Matrix4.diagonal3Values(scale, scale, 1))
        ..translateByDouble(-center.dx, -center.dy, 0, 1);
      final actual = coin.getTransformTo(outer.parent!);
      for (var i = 0; i < 16; i++) {
        expect(actual.storage[i], closeTo(expected.storage[i], .000001));
      }
    }
  });

  for (final phase in ['spin', 'split']) {
    testWidgets('$phase reuses cover art and coin decoration across frames',
        (tester) async {
      final spin = AnimationController(vsync: tester);
      final split = AnimationController(vsync: tester);
      addTearDown(spin.dispose);
      addTearDown(split.dispose);
      if (phase == 'split') split.value = .1;
      await tester.pumpWidget(_host(spin, split));
      await tester.pumpAndSettle();
      var artBuilds = 0;
      var inkBuilds = 0;
      debugOnRebuildDirtyWidget = (element, _) {
        if (element.widget is Image) artBuilds++;
        if (element.widget is Ink) inkBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      for (var i = 1; i <= 20; i++) {
        (phase == 'spin' ? spin : split).value = .1 + i * .03;
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect({'art': artBuilds, 'coin decoration': inkBuilds},
          {'art': 0, 'coin decoration': 0});
    });
  }
}

Widget _host(Animation<double> spin, Animation<double> split,
        {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
          body: Center(
              child: SizedBox(
        width: 300,
        height: 400,
        child: FundReferenceCover(
            type: '红包',
            greeting: '恭喜发财',
            status: '',
            error: null,
            opening: true,
            splitting: false,
            spin: spin,
            split: split,
            onOpen: () {}),
      ))),
    );
