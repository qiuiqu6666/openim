import 'dart:async';
import 'dart:math' as math;

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
  final ratio = tester.view.devicePixelRatio;
  tester.view.viewInsets = FakeViewPadding(bottom: height * ratio);
  tester.view.padding =
      FakeViewPadding(bottom: math.max(0, 34 - height) * ratio);
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
      testWidgets('${brightness.name} $mode takes over the keyboard space',
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
        final panelHeight = mode == 'emoji' ? 314.0 : 282.0;
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
        final keyboardTop = tester.getTopLeft(find.byType(ChatInputBox)).dy;
        expect(focus.hasFocus, isFalse);
        const draft = TextEditingValue(
            text: '未发送草稿', selection: TextSelection.collapsed(offset: 2));
        controller.value = draft;
        // Simulate several frames of an iOS keyboard dismissal.
        for (final height in [240.0, 110.0, 1.0]) {
          await _keyboard(tester, height);
          // Scaffold + panel must occupy max(keyboard, panel), not their sum,
          // and the input must never drop to the bottom between the two.
          expect(tester.getTopLeft(find.byType(ChatInputBox)).dy,
              closeTo(keyboardTop + 320 - math.max(height, panelHeight), .1));
          expect(find.byType(ChatToolBox),
              mode == 'tools' ? findsOneWidget : findsNothing);
          expect(find.byType(ChatEmojiPanel),
              mode == 'emoji' ? findsOneWidget : findsNothing);
          expect(find.byKey(_voice),
              mode == 'voice' ? findsOneWidget : findsNothing);
          expect(tester.takeException(), isNull);
        }
        await _keyboard(tester, 0);
        final settledTop = tester.getTopLeft(find.byType(ChatInputBox)).dy;
        expect(settledTop, closeTo(keyboardTop + 320 - panelHeight, .1));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byType(ChatInputBox)).dy, settledTop,
            reason:
                'no second panel-opening animation after keyboard dismissal');
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

  for (final mode in ['tools', 'emoji', 'voice']) {
    testWidgets('$mode holds its footprint until the keyboard arrives',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await mountToolbox(
          tester,
          ChatInputBox(
            controller: controller,
            onTapVoice: () {},
            toolbox: ToolboxFixture().full(),
            voiceRecordBar: const SizedBox(key: _voice, height: 248),
          ),
          safeBottom: 34,
          bottom: true);
      final tooltip = switch (mode) {
        'tools' => StrRes.add,
        'emoji' => 'sdkEmojiPanel'.tr,
        _ => StrRes.voiceCapture,
      };
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      final panelTop = tester.getTopLeft(find.byType(ChatInputBox)).dy;
      final extent = mode == 'emoji' ? 314.0 : 282.0;
      controller.text = 'draft';
      await tester.pump();
      await tester.tap(mode == 'tools'
          ? find.byKey(const ValueKey('chat-composer-input-fill'))
          : find.byTooltip(mode == 'emoji' ? 'sdkSwitchKeyboard'.tr : tooltip));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      // The voice placeholder and text input differ by one logical pixel.
      expect(tester.getTopLeft(find.byType(ChatInputBox)).dy,
          closeTo(panelTop, 1.1),
          reason:
              'focus must not collapse the panel before the first IME frame');
      for (final inset in [20.0, 140.0, 240.0, 320.0]) {
        await _keyboard(tester, inset);
        expect(tester.getTopLeft(find.byType(ChatInputBox)).dy,
            closeTo(panelTop + extent - math.max(extent, inset), 1.1));
      }
      await tester.pumpAndSettle();
      _expectNoPanels(tester);
      expect(controller.text, 'draft');
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final from in ['emoji', 'voice', 'tools']) {
    for (final to in ['emoji', 'voice', 'tools']) {
      if (from == to) continue;
      testWidgets('$from switches directly to $to without a collapsed frame',
          (tester) async {
        await mountToolbox(
            tester,
            ChatInputBox(
              onTapVoice: () {},
              toolbox: ToolboxFixture().full(),
              voiceRecordBar: const SizedBox(key: _voice, height: 248),
            ),
            safeBottom: 34,
            bottom: true);
        String tooltip(String mode) => switch (mode) {
              'tools' => StrRes.add,
              'emoji' => 'sdkEmojiPanel'.tr,
              _ => StrRes.voiceCapture,
            };
        await tester.tap(find.byTooltip(tooltip(from)));
        await tester.pumpAndSettle();
        final before = tester.getTopLeft(find.byType(ChatInputBox)).dy;
        await tester.tap(find.byTooltip(tooltip(to)));
        await tester.pump();
        final expected = before +
            (from == 'emoji' ? 314 : 282) -
            (to == 'emoji' ? 314 : 282);
        expect(tester.getTopLeft(find.byType(ChatInputBox)).dy,
            closeTo(expected, 1.1));
        await tester.pump(const Duration(milliseconds: 80));
        expect(tester.getTopLeft(find.byType(ChatInputBox)).dy,
            closeTo(expected, 1.1));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(find.byType(ChatInputBox)).dy,
            closeTo(expected, 1.1));
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('short keyboard releases bridge and a new panel cancels it',
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
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-composer-input-fill')));
    await tester.pump();
    await _keyboard(tester, 180);
    expect(tester.getSize(find.byKey(_slot)).height, 102);
    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getSize(find.byKey(_slot)).height, 0);
    await tester.tap(find.byTooltip(StrRes.add));
    await tester.pump();
    await _keyboard(tester, 0);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('chat-composer-input-fill')));
    await tester.pump();
    await tester.tap(find.byTooltip('sdkEmojiPanel'.tr));
    await tester.pump();
    final top = tester.getTopLeft(find.byType(ChatInputBox)).dy;
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChatEmojiPanel), findsOneWidget);
    expect(tester.getTopLeft(find.byType(ChatInputBox)).dy, top);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final ratio in [1.0, 3.0]) {
    testWidgets('keyboard dismissal has no safe-area rebound at DPR $ratio',
        (tester) async {
      await mountToolbox(tester,
          const ChatInputBox(toolbox: SizedBox(), voiceRecordBar: SizedBox()),
          safeBottom: 34, bottom: true);
      tester.view.devicePixelRatio = ratio;
      tester.view.physicalSize = Size(375 * ratio, 812 * ratio);
      tester.view.viewPadding = FakeViewPadding(bottom: 34 * ratio);
      await _keyboard(tester, 320);
      final initialTop = tester.getTopLeft(find.byType(ChatInputBox)).dy;
      for (final height in [240.0, 110.0, 34.0, 20.0, 1.0, 0.0]) {
        await _keyboard(tester, height);
        expect(tester.getTopLeft(find.byType(ChatInputBox)).dy,
            closeTo(initialTop + 320 - math.max(height, 34), .1));
      }
      final finalTop = tester.getTopLeft(find.byType(ChatInputBox)).dy;
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(find.byType(ChatInputBox)).dy, finalTop);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byType(ChatInputBox)).dy, finalTop);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
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
    expect(tester.getSize(find.byKey(_slot)).height, 248);
    // No IME metrics arrive for a hardware keyboard: release the bridge.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
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
