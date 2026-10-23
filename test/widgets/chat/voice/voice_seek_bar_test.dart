import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/voice/voice_seek_bar.dart';

void main() {
  Widget bar(ValueChanged<double>? seek, {double progress = .2}) => SizedBox(
      width: 160,
      child: VoiceSeekBar(
          progress: progress,
          levels: const [],
          color: Colors.grey,
          playedColor: Colors.blue,
          waveHeight: 18,
          onSeek: seek));
  Widget host(Widget child, {Brightness brightness = Brightness.light}) =>
      MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(body: Center(child: child)));

  for (final brightness in Brightness.values) {
    testWidgets('tap seeks without toggling bubble in $brightness',
        (tester) async {
      final values = <double>[];
      var toggles = 0;
      await tester.pumpWidget(host(
          GestureDetector(onTap: () => toggles++, child: bar(values.add)),
          brightness: brightness));
      final rect = tester.getRect(find.byType(VoiceSeekBar));
      expect(rect.height, greaterThanOrEqualTo(48));
      await tester.tapAt(Offset(rect.left + rect.width * .75, rect.center.dy));
      expect(values.single, closeTo(.75, .01));
      expect(toggles, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('drag previews and commits once on release with clamped bounds',
      (tester) async {
    final values = <double>[];
    await tester.pumpWidget(host(bar(values.add)));
    final rect = tester.getRect(find.byType(VoiceSeekBar));
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(values, isEmpty);
    final paint = tester.widget<CustomPaint>(find.descendant(
        of: find.byType(VoiceSeekBar), matching: find.byType(CustomPaint)));
    expect((paint.painter! as VoiceSeekPainter).progress, 1);
    await gesture.up();
    expect(values, [1]);
  });

  testWidgets('vertical drag scrolls list without seeking', (tester) async {
    final values = <double>[];
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(host(ListView(controller: scroll, children: [
      bar(values.add),
      const SizedBox(height: 2000),
    ])));
    await tester.drag(find.byType(VoiceSeekBar), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(values, isEmpty);
  });

  testWidgets('cancelled drag and disabled bar never seek or toggle',
      (tester) async {
    final values = <double>[];
    await tester.pumpWidget(host(bar(values.add)));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(VoiceSeekBar)));
    await gesture.moveBy(const Offset(40, 0));
    await gesture.cancel();
    await tester.pump();
    expect(values, isEmpty);
    var toggles = 0;
    await tester.pumpWidget(
        host(GestureDetector(onTap: () => toggles++, child: bar(null))));
    await tester.tap(find.byType(VoiceSeekBar));
    expect(toggles, 0);
  });

  testWidgets('screen reader can adjust progress without dragging',
      (tester) async {
    final semantics = tester.ensureSemantics();

    final values = <double>[];
    await tester.pumpWidget(host(bar(values.add)));
    final node = tester.getSemantics(find.byType(VoiceSeekBar));
    expect(node.getSemanticsData().hasAction(SemanticsAction.increase), isTrue);
    tester
        .renderObject(find.byType(VoiceSeekBar))
        .owner!
        .semanticsOwner!
        .performAction(node.id, SemanticsAction.increase);
    expect(values.single, closeTo(.3, .001));
    semantics.dispose();
  });
}
