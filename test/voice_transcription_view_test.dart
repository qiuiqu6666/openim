import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

Future<void> pumpTranscript(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
  Locale locale = const Locale('zh', 'CN'),
  double textScale = 1,
  double width = 200,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(GetMaterialApp(
    translations: TranslationService(),
    locale: locale,
    theme: ThemeData(brightness: brightness),
    home: Scaffold(
      body: MediaQuery(
        data: MediaQueryData(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: disableAnimations,
        ),
        child: SingleChildScrollView(
          child: Center(child: SizedBox(width: width, child: child)),
        ),
      ),
    ),
  ));
}

void main() {
  tearDown(Get.reset);

  test('empty and whitespace results are not transcripts', () {
    expect(const VoiceTranscriptionState().hasText, isFalse);
    expect(const VoiceTranscriptionState(text: ' \n ').hasText, isFalse);
    expect(const VoiceTranscriptionState(text: ' 你好 ').hasText, isTrue);
    expect(const VoiceTranscriptionState().expanded, isTrue);
  });

  testWidgets('loading communicates progress and blocks retry actions',
      (tester) async {
    var retries = 0;
    await pumpTranscript(
      tester,
      VoiceTranscriptionView(
        state: const VoiceTranscriptionState(loading: true),
        onRetry: () => retries++,
      ),
    );
    expect(find.text('转文字中…'), findsOneWidget);
    expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
    expect(
      tester
          .widget<Semantics>(
              find.byKey(const ValueKey('voice-transcription-loading')))
          .properties
          .liveRegion,
      isTrue,
    );
    expect(find.byType(TextButton), findsNothing);
    expect(retries, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transcript is selectable and can expand from three lines',
      (tester) async {
    var expanded = false;
    const text = '第一行语音。\n第二行语音。\n第三行语音。\n第四行语音。';
    await pumpTranscript(
      tester,
      StatefulBuilder(builder: (context, setState) {
        return VoiceTranscriptionView(
          state: VoiceTranscriptionState(text: text, expanded: expanded),
          onToggle: () => setState(() => expanded = !expanded),
        );
      }),
    );
    final collapsed =
        tester.widget<SelectableText>(find.byType(SelectableText));
    expect(collapsed.data, text);
    expect(collapsed.maxLines, 3);
    expect(find.text('展开文字'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('voice-transcription-toggle')))
          .height,
      greaterThanOrEqualTo(48),
    );
    await tester.tap(find.text('展开文字'));
    await tester.pump();
    expect(expanded, isTrue);
    expect(
      tester.widget<SelectableText>(find.byType(SelectableText)).maxLines,
      isNull,
    );
    expect(find.text('收起文字'), findsOneWidget);
    await tester.tap(find.text('收起文字'));
    await tester.pump();
    expect(expanded, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'failure includes detail and retries without overflow in dark mode',
      (tester) async {
    var retries = 0;
    await pumpTranscript(
      tester,
      VoiceTranscriptionView(
        state: const VoiceTranscriptionState(error: 'voiceToTextUnavailable'),
        onRetry: () => retries++,
      ),
      brightness: Brightness.dark,
      textScale: 2,
      width: 160,
    );
    expect(find.text('转文字失败'), findsOneWidget);
    expect(find.text('语音识别服务暂不可用，请稍后重试'), findsOneWidget);
    await tester.tap(find.text('重试转文字'));
    await tester.pump();
    expect(retries, 1);
    final detail = tester.widget<Text>(find.text('语音识别服务暂不可用，请稍后重试'));
    expect(
      detail.style?.color,
      Theme.of(tester.element(find.byType(VoiceTranscriptionView)))
          .colorScheme
          .onSurfaceVariant,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty result offers retry in English', (tester) async {
    await pumpTranscript(
      tester,
      VoiceTranscriptionView(
        state: const VoiceTranscriptionState(text: ' '),
        onRetry: () {},
      ),
      locale: const Locale('en', 'US'),
    );
    expect(find.text('No speech was recognized'), findsOneWidget);
    expect(find.text('Retry transcription'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
  });

  testWidgets('rate limiting and timeout explain when to retry',
      (tester) async {
    for (final key in ['voiceToTextRateLimited', 'voiceToTextTimeout']) {
      var retries = 0;
      await pumpTranscript(
        tester,
        VoiceTranscriptionView(
          state: VoiceTranscriptionState(error: key),
          onRetry: () => retries++,
        ),
        brightness: Brightness.dark,
        textScale: 2,
        width: 200,
      );
      expect(find.text(key.tr), findsOneWidget);
      await tester.tap(find.text('重试转文字'));
      await tester.pump();
      expect(retries, 1);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('short results stay compact without a redundant folding action',
      (tester) async {
    var toggles = 0;
    await pumpTranscript(
      tester,
      VoiceTranscriptionView(
        state: const VoiceTranscriptionState(text: ' 你好，明天见。 '),
        onToggle: () => toggles++,
      ),
    );
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.data, '你好，明天见。');
    expect(find.byType(TextButton), findsNothing);
    expect(toggles, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a nonselectable transcript keeps folding without selection UI',
      (tester) async {
    var expanded = false;
    const text = '第一行。\n第二行。\n第三行。\n第四行。';
    await pumpTranscript(
      tester,
      StatefulBuilder(builder: (context, setState) {
        return VoiceTranscriptionView(
          state: VoiceTranscriptionState(text: text, expanded: expanded),
          selectable: false,
          onToggle: () => setState(() => expanded = !expanded),
        );
      }),
    );
    final transcript = find.byKey(const ValueKey('voice-transcription-text'));
    expect(find.byType(SelectableText), findsNothing);
    expect(tester.widget<Text>(transcript).overflow, TextOverflow.ellipsis);
    await tester.tap(find.text('展开文字'));
    await tester.pump();
    expect(tester.widget<Text>(transcript).maxLines, isNull);
    expect(find.byType(SelectableText), findsNothing);
    expect(expanded, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps progress readable without spinning',
      (tester) async {
    await pumpTranscript(
      tester,
      VoiceTranscriptionView(
        state: const VoiceTranscriptionState(
          loading: true,
          text: 'An earlier result',
          error: 'voiceToTextTimeout',
        ),
        onToggle: () {},
        onRetry: () {},
      ),
      disableAnimations: true,
    );
    expect(
      tester
          .widget<CupertinoActivityIndicator>(
              find.byType(CupertinoActivityIndicator))
          .animating,
      isFalse,
    );
    expect(find.text('转文字中…'), findsOneWidget);
    expect(find.byType(SelectableText), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('转文字失败'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure uses one announcement and an accessible retry target',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await pumpTranscript(
        tester,
        VoiceTranscriptionView(
          state: const VoiceTranscriptionState(error: 'voiceToTextFailed'),
          onRetry: () {},
        ),
        width: 160,
        textScale: 2,
      );
      expect(find.text('转文字失败'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(
                find.byKey(const ValueKey('voice-transcription-feedback')))
            .properties
            .liveRegion,
        isTrue,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final dark in [false, true]) {
    for (final locale in [const Locale('zh', 'CN'), const Locale('en', 'US')]) {
      testWidgets(
          'narrow large text handles all states / dark=$dark / locale=$locale',
          (tester) async {
        const longText = '第一段语音文字用于确认窄屏下正常换行。\n第二段保持可选文字。\n第三段文字。\n第四段文字。';
        final states = [
          const VoiceTranscriptionState(loading: true),
          const VoiceTranscriptionState(text: longText, expanded: false),
          const VoiceTranscriptionState(text: longText),
          const VoiceTranscriptionState(error: 'voiceToTextUnavailable'),
          const VoiceTranscriptionState(text: ' '),
        ];
        for (final state in states) {
          await pumpTranscript(
            tester,
            VoiceTranscriptionView(
              state: state,
              onToggle: () {},
              onRetry: () {},
            ),
            brightness: dark ? Brightness.dark : Brightness.light,
            locale: locale,
            width: 160,
            textScale: 2,
          );
          final view = tester
              .getRect(find.byKey(const ValueKey('voice-transcription-view')));
          for (final button in find.byType(TextButton).evaluate()) {
            final bounds = tester.getRect(find.byWidget(button.widget));
            expect(bounds.left, greaterThanOrEqualTo(view.left));
            expect(bounds.right, lessThanOrEqualTo(view.right));
            expect(bounds.height, greaterThanOrEqualTo(48));
          }
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
