import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_emoji_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/toolbox_fixture.dart';

const _slotKey = ValueKey('chat-toolbox-panel-slot');

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} expanded tools use one safe inset and retain draft across modes and closing',
        (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      final close = StreamController<void>();
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        focus.dispose();
        await close.close();
      });
      final fixture = ToolboxFixture();
      await mountToolbox(
          tester,
          ChatInputBox(
            controller: controller,
            focusNode: focus,
            forceCloseToolboxSub: close.stream,
            onTapVoice: () {},
            onSend: (_) {},
            toolbox: fixture.full(),
            voiceRecordBar: const SizedBox(
              height: 248,
              child: Text('voice-panel-fixture'),
            ),
          ),
          brightness: brightness,
          safeBottom: 34,
          bottom: true);

      await tester.tap(find.byTooltip(StrRes.add));
      await tester.pump();
      final slot = find.byKey(_slotKey);
      await tester.pump(const Duration(milliseconds: 100));
      final midHeight = tester.getSize(slot).height;
      expect(midHeight, greaterThan(34));
      expect(midHeight, lessThan(282));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getSize(slot).height, closeTo(248 + 34, .1));
      final panel = tester.getRect(find.byType(ChatToolBox));
      final composer = tester.getRect(find.byType(ChatInputBox));
      expect(panel.height, closeTo(248 + 34, .1));
      expect(composer.bottom, 812);
      expect(panel.bottom, composer.bottom,
          reason: 'the system bottom inset belongs to the panel only once');
      final lastIndicator = tester
          .getRect(find.byKey(const ValueKey('chat-toolbox-indicator-1')));
      expect(lastIndicator.bottom, lessThanOrEqualTo(panel.bottom - 34));
      expect(find.byType(ChatEmojiPanel), findsNothing);
      expect(find.text('voice-panel-fixture').hitTestable(), findsNothing);

      const draft = TextEditingValue(
          text: '未发送的草稿', selection: TextSelection.collapsed(offset: 2));
      controller.value = draft;
      await tester.pump();
      await tester.tap(find.byTooltip('sdkEmojiPanel'.tr));
      await tester.pumpAndSettle();
      expect(find.byType(ChatToolBox).hitTestable(), findsNothing);
      expect(find.byType(ChatEmojiPanel), findsOneWidget);
      expect(controller.value, draft);
      await tester.tap(find.byTooltip(StrRes.voiceCapture));
      await tester.pumpAndSettle();
      expect(find.byType(ChatEmojiPanel), findsNothing);
      expect(find.byType(ChatToolBox).hitTestable(), findsNothing);
      expect(find.text('voice-panel-fixture').hitTestable(), findsOneWidget);
      expect(controller.value, draft);

      // More is available while the text field is empty. Restore a real draft
      // once it is open, then verify both focus and the page close stream.
      controller.clear();
      await tester.pump();
      await tester.tap(find.byTooltip(StrRes.add));
      await tester.pumpAndSettle();
      expect(find.text('voice-panel-fixture').hitTestable(), findsNothing);
      expect(find.byType(ChatToolBox).hitTestable(), findsOneWidget);
      controller.value = draft;
      await tester.pump();
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(focus.hasFocus, isTrue);
      expect(find.byType(ChatToolBox).hitTestable(), findsNothing);
      expect(tester.getSize(slot).height, closeTo(34, .1));
      expect(controller.value, draft);

      focus.unfocus();
      controller.clear();
      await tester.pump();
      await tester.tap(find.byTooltip(StrRes.add));
      await tester.pumpAndSettle();
      controller.value = draft;
      await tester.pump();
      close.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ChatToolBox).hitTestable(), findsNothing);
      expect(find.byType(ChatEmojiPanel), findsNothing);
      expect(find.text('voice-panel-fixture').hitTestable(), findsNothing);
      expect(tester.getSize(slot).height, closeTo(34, .1));
      expect(controller.value, draft);
      expect(tester.takeException(), isNull);
    });
  }
}
