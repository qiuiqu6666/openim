import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/unicode/unicode_samples.dart';

Future<void> _mount(WidgetTester tester, TextEditingController controller,
    {TargetPlatform platform = TargetPlatform.android,
    Brightness brightness = Brightness.light,
    ValueChanged<String>? onSend}) async {
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(platform: platform, brightness: brightness),
      home: Scaffold(
          body: ChatInputBox(
        controller: controller,
        toolbox: const SizedBox.shrink(),
        voiceRecordBar: const SizedBox.shrink(),
        onSend: onSend,
      )),
    ),
  ));
  await tester.tap(find.byType(ChatTextField));
  await tester.pump();
  expect(tester.testTextInput.isRegistered, isTrue);
}

void main() {
  setUp(() {
    Get.testMode = true;
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(Get.reset);
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final brightness in Brightness.values) {
      testWidgets('keyboard sequences remain raw: $platform/$brightness',
          (tester) async {
        final controller = TextEditingController();
        await _mount(tester, controller,
            platform: platform, brightness: brightness);
        for (final sample in unicodeSamples) {
          final raw = '中文 ${sample.text}';
          final value = TextEditingValue(
              text: raw,
              selection: TextSelection.collapsed(offset: raw.length),
              composing: TextRange(start: 3, end: raw.length));
          tester.testTextInput.updateEditingValue(value);
          await tester.pump();
          expect(controller.value, value, reason: sample.name);
          final editable = tester.allRenderObjects
              .whereType<ExtendedRenderEditable>()
              .single;
          expect(editable.text!.toPlainText(), raw, reason: sample.name);
          tester.testTextInput
              .updateEditingValue(value.copyWith(composing: TextRange.empty));
          await tester.pump();
          expect(controller.text.codeUnits, raw.codeUnits);
          expect(tester.takeException(), isNull);
        }
        // No legacy Android workaround may append whitespace at 63 code units.
        final sixtyThree = '${List.filled(61, 'a').join()}\u{1F602}';
        tester.testTextInput.enterText(sixtyThree);
        await tester.pump();
        expect(controller.text, sixtyThree);
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
  }

  testWidgets('standard keyboard backspace removes whole clusters',
      (tester) async {
    final controller = TextEditingController();
    await _mount(tester, controller);
    for (final sample in unicodeSamples) {
      for (final cluster in sample.text.characters) {
        final source = 'A$cluster';
        tester.testTextInput.enterText(source);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.pump();
        expect(controller.text, 'A', reason: sample.name);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('picker accepts a saved sequence absent from its catalog',
      (tester) async {
    const raw = '\u{1FAEA}\u200D\u{1F4BB}';
    SharedPreferences.setMockInitialValues({
      'chat_favorite_emoji': [raw]
    });
    final controller = TextEditingController();
    await _mount(tester, controller);
    await tester.tap(find.byTooltip('表情面板'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收藏表情'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('emoji-$raw')));
    expect(controller.text, raw);
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.tap(find.byTooltip('删除表情'));
    expect(controller.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('send callback retains leading and trailing Unicode text',
      (tester) async {
    final controller = TextEditingController();
    String? sent;
    await _mount(tester, controller, onSend: (value) => sent = value);
    const raw = ' \u0301\u2193\uFE0F \n';
    tester.testTextInput.enterText(raw);
    await tester.pump();
    final panel = tester.widget<ChatInputBox>(find.byType(ChatInputBox));
    // Exercise the same public state action used by send buttons/IME completion.
    final field = tester.widget<ChatTextField>(find.byType(ChatTextField));
    field.onEditingComplete!();
    expect(sent, raw);
    expect(panel.controller!.text, raw);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
