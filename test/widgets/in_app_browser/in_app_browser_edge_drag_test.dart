import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/in_app_browser/in_app_browser_edge_drag.dart';

void main() {
  testWidgets('edge drag ignores scroll, taps, horizontal swipes and pinch',
      (tester) async {
    var atTop = false;
    var starts = 0;
    var cancels = 0;
    var ends = 0;
    var distance = 0.0;
    await tester.pumpWidget(MaterialApp(
        home: InAppBrowserEdgeDrag(
      atTop: () => atTop,
      onStart: () => starts++,
      onUpdate: (delta) => distance += delta,
      onEnd: (_) => ends++,
      onCancel: () => cancels++,
      child: const SizedBox.expand(),
    )));
    await tester.drag(find.byType(InAppBrowserEdgeDrag), const Offset(0, 100));
    expect(starts, 0);
    atTop = true;
    await tester.tap(find.byType(InAppBrowserEdgeDrag));
    expect(starts, 0);
    var gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(80, 0));
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    expect(starts, 0);
    gesture = await tester.startGesture(const Offset(100, 100), pointer: 1);
    await gesture.moveBy(const Offset(0, 40));
    expect(starts, 1);
    expect(distance, greaterThan(0));
    final second =
        await tester.startGesture(const Offset(150, 100), pointer: 2);
    expect(cancels, 1);
    await second.up();
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    expect(starts, 1);
    expect(ends, 0);
    gesture = await tester.startGesture(const Offset(100, 100));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.cancel();
    expect(cancels, 2);
    await tester.drag(find.byType(InAppBrowserEdgeDrag), const Offset(0, 100));
    expect(ends, 1);
  });
}
