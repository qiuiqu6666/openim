import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/src/widgets/chat/chat_emoji_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _bar = ValueKey('chat-disabled-input-bar');
const _draft = TextEditingValue(
  text: '保留这条未发送草稿',
  selection: TextSelection(baseOffset: 2, extentOffset: 5),
);

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Get.reset);

  for (final dark in [false, true]) {
    testWidgets('mute and unmute preserve draft and selection / dark=$dark',
        (tester) async {
      final fixture = await _DisabledComposer.mount(tester, dark: dark);
      fixture.controller.value = _draft;
      fixture.focus.requestFocus();
      await tester.pumpAndSettle();
      expect(fixture.focus.hasFocus, isTrue);
      expect(fixture.controller.value, _draft);

      fixture.availability.value = const _Availability(enabled: false);
      await tester.pumpAndSettle();
      expect(find.text(StrRes.youMuted), findsOneWidget);
      expect(find.byKey(_bar), findsOneWidget);
      expect(find.byType(ChatTextField), findsNothing);
      expect(find.widgetWithText(ElevatedButton, StrRes.send), findsNothing);
      expect(fixture.focus.hasFocus, isFalse);
      expect(fixture.controller.value, _draft);
      expect(fixture.sent, isEmpty);

      fixture.availability.value = const _Availability();
      await tester.pumpAndSettle();
      expect(find.byKey(_bar), findsNothing);
      expect(find.byType(ChatTextField), findsOneWidget);
      expect(fixture.controller.value, _draft);
      expect(fixture.focus.hasFocus, isFalse);
      await tester.tap(find.widgetWithText(ElevatedButton, StrRes.send));
      expect(fixture.sent, [_draft.text]);
      expect(fixture.controller.value, _draft);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mute closes every composer panel and does not reopen / $dark',
        (tester) async {
      final fixture = await _DisabledComposer.mount(tester, dark: dark);
      for (final mode in ['emoji', 'tools', 'voice']) {
        fixture.controller.clear();
        await tester.pump();
        await tester.tap(switch (mode) {
          'emoji' => find.byTooltip('sdkEmojiPanel'.tr),
          'tools' => find.byTooltip(StrRes.add),
          _ => find.byTooltip(StrRes.voiceCapture),
        });
        await tester.pumpAndSettle();
        switch (mode) {
          case 'emoji':
            expect(find.byType(ChatEmojiPanel), findsOneWidget);
          case 'tools':
            expect(find.text('tool-panel-fixture').hitTestable(), findsOneWidget);
          case 'voice':
            expect(find.text('voice-panel-fixture').hitTestable(), findsOneWidget);
        }
        fixture.controller.value = _draft;
        await tester.pump();

        fixture.availability.value = const _Availability(
          enabled: false,
          hint: '群主已开启全员禁言',
        );
        await tester.pumpAndSettle();
        expect(find.text('群主已开启全员禁言'), findsOneWidget);
        expect(find.byType(ChatEmojiPanel), findsNothing);
        expect(find.text('tool-panel-fixture').hitTestable(), findsNothing);
        expect(find.text('voice-panel-fixture'), findsNothing);
        expect(fixture.controller.value, _draft);
        expect(fixture.focus.hasFocus, isFalse);
        expect(fixture.sent, isEmpty);

        fixture.availability.value = const _Availability();
        await tester.pumpAndSettle();
        expect(find.byType(ChatTextField), findsOneWidget);
        expect(find.byType(ChatEmojiPanel), findsNothing);
        expect(find.text('tool-panel-fixture').hitTestable(), findsNothing);
        expect(find.text('voice-panel-fixture'), findsNothing);
        expect(fixture.controller.value, _draft);
        expect(fixture.focus.hasFocus, isFalse);
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('blocked bar fits narrow large text and one safe inset / $dark',
        (tester) async {
      const longHint = '当前群聊已开启全员禁言，请等待管理员解除后再发送消息';
      final fixture = await _DisabledComposer.mount(
        tester,
        dark: dark,
        size: const Size(320, 640),
        textScale: 2,
        initial: const _Availability(enabled: false, hint: longHint),
      );
      for (final inset in [0.0, 34.0]) {
        tester.view.padding = FakeViewPadding(bottom: inset);
        tester.view.viewPadding = FakeViewPadding(bottom: inset);
        for (final exited in [false, true]) {
          fixture.availability.value = _Availability(
            enabled: false,
            exited: exited,
            hint: longHint,
          );
          await tester.pumpAndSettle();
          final message = exited ? StrRes.notSendMessageNotInGroup : longHint;
          final composer = tester.getRect(find.byType(ChatInputBox));
          final bar = tester.getRect(find.byKey(_bar));
          final label = tester.getRect(find.text(message));
          final warning = tester.getRect(_warningImage());
          expect(composer.width, 320);
          expect(composer.bottom, 640);
          expect(bar.bottom, closeTo(640 - inset, .1));
          expect(composer.height, closeTo(bar.height + inset, .1),
              reason: 'The bottom safe inset belongs to the disabled bar once');
          expect(bar.contains(label.topLeft), isTrue);
          expect(bar.contains(label.bottomRight - const Offset(.01, .01)), isTrue);
          expect(bar.contains(warning.topLeft), isTrue);
          expect(warning.right, lessThan(label.left));
          expect(warning.center.dy, closeTo(label.center.dy, .1));
          expect((warning.left + label.right) / 2, closeTo(bar.center.dx, .1));
          expect(tester.widget<Text>(find.text(message)).textAlign,
              TextAlign.center);
          expect(tester.widget<Container>(find.byKey(_bar)).color,
              dark ? const Color(0xFF101114) : const Color(0xFFFFFFFF));
          expect(find.byType(ChatTextField), findsNothing);
          expect(tester.takeException(), isNull);
        }
      }
    });
  }

  testWidgets('leaving a group takes precedence over any muted message',
      (tester) async {
    final fixture = await _DisabledComposer.mount(tester);
    fixture.controller.value = _draft;
    for (final enabled in [true, false]) {
      fixture.availability.value = _Availability(
        enabled: enabled,
        exited: true,
        hint: '群主已开启全员禁言',
      );
      await tester.pumpAndSettle();
      expect(find.text(StrRes.notSendMessageNotInGroup), findsOneWidget);
      expect(find.text('群主已开启全员禁言'), findsNothing);
      expect(find.byType(ChatTextField), findsNothing);
      expect(fixture.controller.value, _draft);
      expect(fixture.sent, isEmpty);
    }
    expect(tester.takeException(), isNull);
  });
}

Finder _warningImage() => find.byWidgetPredicate((widget) =>
    widget is Image &&
    widget.image is AssetImage &&
    (widget.image as AssetImage).assetName == ImageRes.warn);

class _Availability {
  const _Availability({this.enabled = true, this.exited = false, this.hint});
  final bool enabled;
  final bool exited;
  final String? hint;
}

class _DisabledComposer {
  _DisabledComposer(_Availability initial)
      : availability = ValueNotifier(initial);

  final TextEditingController controller = TextEditingController();
  final FocusNode focus = FocusNode();
  final ValueNotifier<_Availability> availability;
  final sent = <String>[];

  static Future<_DisabledComposer> mount(
    WidgetTester tester, {
    bool dark = false,
    Size size = const Size(375, 812),
    double textScale = 1,
    _Availability initial = const _Availability(),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    final wasDark = Styles.isDark;
    Styles.isDark = dark;
    final fixture = _DisabledComposer(initial);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      fixture.controller.dispose();
      fixture.focus.dispose();
      fixture.availability.dispose();
      Styles.isDark = wasDark;
    });
    await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: Column(children: [
            const Spacer(),
            ValueListenableBuilder<_Availability>(
              valueListenable: fixture.availability,
              builder: (_, state, __) => ChatInputBox(
                controller: fixture.controller,
                focusNode: fixture.focus,
                enabled: state.enabled,
                isNotInGroup: state.exited,
                hintText: state.hint,
                onTapVoice: () {},
                onSend: fixture.sent.add,
                toolbox: const SizedBox(
                    height: 248, child: Text('tool-panel-fixture')),
                voiceRecordBar: const SizedBox(
                    height: 248, child: Text('voice-panel-fixture')),
              ),
            ),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return fixture;
  }
}
