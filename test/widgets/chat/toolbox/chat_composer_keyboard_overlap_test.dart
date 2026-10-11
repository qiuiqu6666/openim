import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_emoji_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/toolbox_fixture.dart';

const _slot = ValueKey('chat-toolbox-panel-slot');
const _voice = ValueKey('keyboard-test-voice');

Future<void> _keyboard(WidgetTester tester, double height) async {
  tester.view.viewInsets = FakeViewPadding(bottom: height);
  tester.view.padding = FakeViewPadding(bottom: height > 0 ? 0 : 34);
  await tester.pump();
}

void _expectNoPanels(WidgetTester tester) {
  expect(find.byType(ChatToolBox), findsNothing);
  expect(find.byType(ChatEmojiPanel), findsNothing);
  expect(find.byKey(_voice), findsNothing);
  expect(tester.getSize(find.byKey(_slot)).height, 0);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    for (final mode in ['tools', 'emoji', 'voice']) {
      testWidgets('${brightness.name} $mode waits for native keyboard to close',
          (tester) async {
        final focus = FocusNode();
        final controller = TextEditingController();
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          focus.dispose();
          controller.dispose();
        });
        await mountToolbox(
          tester,
          ChatInputBox(
            controller: controller,
            focusNode: focus,
            quoteContent: '一条引用消息',
            directionalText: const TextSpan(text: '定向发送给成员'),
            onTapVoice: () {},
            toolbox: ToolboxFixture().full(),
            voiceRecordBar: const SizedBox(key: _voice, height: 248),
          ),
          brightness: brightness,
          safeBottom: 34,
          bottom: true,
        );
        focus.requestFocus();
        await tester.pump();
        await _keyboard(tester, 320);
        expect(
            MediaQuery.viewInsetsOf(tester.element(find.byType(ChatInputBox)))
                .bottom,
            0,
            reason: 'Scaffold already consumed the native keyboard inset');
        await tester.tap(find.byTooltip(switch (mode) {
          'tools' => StrRes.add,
          'emoji' => 'sdkEmojiPanel'.tr,
          _ => StrRes.voiceCapture,
        }));
        await tester.pump();
        _expectNoPanels(tester);
        expect(focus.hasFocus, isFalse);
        const draft = TextEditingValue(
            text: '未发送草稿', selection: TextSelection.collapsed(offset: 2));
        controller.value = draft;
        // Simulate several frames of an iOS keyboard dismissal.
        for (final height in [240.0, 110.0, 1.0]) {
          await _keyboard(tester, height);
          _expectNoPanels(tester);
        }
        await _keyboard(tester, 0);
        await tester.pumpAndSettle();
        expect(find.byType(ChatToolBox),
            mode == 'tools' ? findsOneWidget : findsNothing);
        expect(find.byType(ChatEmojiPanel),
            mode == 'emoji' ? findsOneWidget : findsNothing);
        expect(find.byKey(_voice),
            mode == 'voice' ? findsOneWidget : findsNothing);
        expect(controller.value, draft);

        // A restored native keyboard must remove panel height immediately,
        // even without a focus notification.
        await _keyboard(tester, 320);
        _expectNoPanels(tester);
        focus.requestFocus();
        await tester.pump();
        await _keyboard(tester, 0);
        await tester.pumpAndSettle();
        expect(find.byType(ChatToolBox), findsNothing);
        expect(find.byType(ChatEmojiPanel), findsNothing);
        expect(find.byKey(_voice), findsNothing);
        expect(controller.value, draft);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('rapid mode changes and forced close cancel pending panels',
      (tester) async {
    final close = StreamController<void>();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await close.close();
    });
    await mountToolbox(
        tester,
        ChatInputBox(
          forceCloseToolboxSub: close.stream,
          onTapVoice: () {},
          toolbox: ToolboxFixture().full(),
          voiceRecordBar: const SizedBox(key: _voice, height: 248),
        ),
        bottom: true,
        safeBottom: 34);
    await _keyboard(tester, 320);
    for (final tooltip in [
      StrRes.add,
      'sdkEmojiPanel'.tr,
      StrRes.voiceCapture
    ]) {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pump();
      _expectNoPanels(tester);
    }
    close.add(null);
    await tester.pump();
    await _keyboard(tester, 0);
    await tester.pumpAndSettle();
    expect(find.byType(ChatToolBox), findsNothing);
    expect(find.byType(ChatEmojiPanel), findsNothing);
    expect(find.byKey(_voice), findsNothing);
  });

  testWidgets('internally owned input focus closes tools on text field tap',
      (tester) async {
    await mountToolbox(
        tester,
        ChatInputBox(
          toolbox: ToolboxFixture().full(),
          voiceRecordBar: const SizedBox(),
        ),
        bottom: true);
    await tester.tap(find.byTooltip(StrRes.add));
    await tester.pumpAndSettle();
    expect(find.byType(ChatToolBox), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat-composer-input-fill')));
    await tester.pumpAndSettle();
    expect(find.byType(ChatToolBox), findsNothing);
    expect(tester.getSize(find.byKey(_slot)).height, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'keyboard restoration interrupts panel opening without leftover height',
      (tester) async {
    await mountToolbox(
        tester,
        ChatInputBox(
          toolbox: ToolboxFixture().full(),
          voiceRecordBar: const SizedBox(),
        ),
        bottom: true,
        safeBottom: 34);
    await tester.tap(find.byTooltip(StrRes.add));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.getSize(find.byKey(_slot)).height, greaterThan(34));
    expect(tester.getSize(find.byKey(_slot)).height, lessThan(282));
    await _keyboard(tester, 320);
    _expectNoPanels(tester);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    _expectNoPanels(tester);
    // Tapping the input cancels the pending panel even if the keyboard was
    // restored without a Flutter focus event.
    await tester.tap(find.byKey(const ValueKey('chat-composer-input-fill')));
    await tester.pump();
    await _keyboard(tester, 0);
    await tester.pumpAndSettle();
    expect(find.byType(ChatToolBox), findsNothing);
    expect(tester.getSize(find.byKey(_slot)).height, 34);
    await tester.pumpWidget(const SizedBox());
  });
}
