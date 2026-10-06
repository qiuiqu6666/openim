import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'support/toolbox_fixture.dart';

void main() {
  setUpAll(loadToolboxPreviewFonts);
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} first page follows the actual phone toolbar order',
        (tester) async {
      final fixture = ToolboxFixture();
      await mountToolbox(tester, fixture.full(), brightness: brightness);
      const firstPage = [
        'album',
        'camera',
        'favorites',
        'call',
        'card',
        'file',
        'red-packet',
        'transfer'
      ];
      final rects = [
        for (final id in firstPage)
          tester.getRect(toolboxAction(id).hitTestable())
      ];
      for (var index = 0; index < rects.length; index++) {
        expect(rects[index].width, greaterThanOrEqualTo(48));
        expect(rects[index].height, greaterThanOrEqualTo(48));
        if (index % 4 != 0) {
          expect(
              rects[index].center.dx, greaterThan(rects[index - 1].center.dx));
          expect(rects[index].top, closeTo(rects[index - 1].top, .1));
        }
      }
      expect(rects[4].top, greaterThan(rects[0].bottom));
      expect(toolboxAction('location').hitTestable(), findsNothing);
      await captureToolbox(tester, brightness, 1);
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      expect(toolboxAction('location').hitTestable(), findsOneWidget);
      await captureToolbox(tester, brightness, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '${brightness.name} small screen large text keeps actions and semantics reachable',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final fixture = ToolboxFixture();
        await mountToolbox(tester, fixture.full(),
            brightness: brightness, size: const Size(320, 568), textScale: 2);
        for (final id in ['album', 'transfer', 'location', 'emoji']) {
          await reachToolboxAction(tester, id);
          final action = toolboxAction(id).hitTestable();
          expect(action, findsOneWidget);
          final rect = tester.getRect(action);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
          expect(rect.height, greaterThanOrEqualTo(48));
          final data = tester.getSemantics(action).getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.hasAction(SemanticsAction.tap), isTrue);
          expect(data.label, isNotEmpty);
        }
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
        '${brightness.name} album without an available callback stays visibly disabled',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mountToolbox(tester, const ChatToolBox(), brightness: brightness);
        final action = toolboxAction('album');
        expect(action, findsOneWidget);
        expect(find.text(StrRes.toolboxAlbum), findsOneWidget);
        expect(
            tester
                .getSemantics(action)
                .getSemanticsData()
                .hasAction(SemanticsAction.tap),
            isFalse);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
}
