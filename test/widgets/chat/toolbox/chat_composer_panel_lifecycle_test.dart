import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim_common/src/widgets/chat/composer/chat_composer_panel_viewport.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets('interrupted panel settles with reduceMotion=$reduceMotion',
        (tester) async {
      const slot = ValueKey('panel');
      Future<void> show({required bool visible, bool interrupt = false}) =>
          tester.pumpWidget(MaterialApp(
            home: MediaQuery(
              data:
                  MediaQueryData(disableAnimations: interrupt && reduceMotion),
              child: TickerMode(
                enabled: !interrupt || reduceMotion,
                child: Align(
                  child: ChatComposerPanelViewport(
                    viewportKey: slot,
                    visible: visible,
                    panelHeight: 240,
                    collapsedHeight: 24,
                    animate: true,
                    child: const SizedBox(),
                  ),
                ),
              ),
            ),
          ));
      await show(visible: false);
      await show(visible: true);
      await tester.pump(const Duration(milliseconds: 40));
      expect(
          tester.getSize(find.byKey(slot)).height, inExclusiveRange(24, 240));
      await show(visible: true, interrupt: true);
      expect(tester.getSize(find.byKey(slot)).height, 240);
      await show(visible: false, interrupt: true);
      expect(tester.getSize(find.byKey(slot)).height, 24);
      await show(visible: false);
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getSize(find.byKey(slot)).height, 24);
    });
  }

  testWidgets('covered chat settles panel before returning to messages',
      (tester) async {
    const slot = ValueKey('panel');
    Future<void> show({required bool visible, required bool ticking}) =>
        tester.pumpWidget(MaterialApp(
          home: TickerMode(
            enabled: ticking,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ChatComposerPanelViewport(
                viewportKey: slot,
                visible: visible,
                panelHeight: 240,
                collapsedHeight: 24,
                animate: true,
                child: const SizedBox(),
              ),
            ),
          ),
        ));

    await show(visible: true, ticking: true);
    expect(tester.getSize(find.byKey(slot)).height, 240);
    await show(visible: false, ticking: false);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.getSize(find.byKey(slot)).height, 24);
    await show(visible: false, ticking: true);
    expect(tester.getSize(find.byKey(slot)).height, 24);
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.getSize(find.byKey(slot)).height, 24);
  });
}
