import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/composer/ai_assistant_draft.dart';
import 'package:openim/pages/ai_assistant/models/ai_assistant_models.dart';
import 'package:openim/pages/ai_assistant/presentation/ai_assistant_widgets.dart';

import 'support/ai_ui_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeAiUiTests);
  tearDown(resetAiUiTests);

  for (final dark in [false, true]) {
    testWidgets('empty state starts one chat and welcome dismisses ($dark)',
        (tester) async {
      final h = AiUiTestHost(dark: dark);
      var starts = 0;
      var closes = 0;
      await h.mount(
          tester,
          h.scaffold((context) => Column(children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: AiWelcomeBanner(
                      dark: dark,
                      i18n: AiAssistantI18n.of(context),
                      onClose: () => closes++),
                ),
                Expanded(
                    child: AiEmptyChatArt(
                        dark: dark,
                        i18n: AiAssistantI18n.of(context),
                        onStart: () => starts++)),
              ])));
      await tester.tap(find.text('开始新对话'));
      await tester.tap(find.byTooltip('关闭'));
      expect((starts, closes), (1, 1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('four guide pages finish only through the final start button',
      (tester) async {
    var finished = 0;
    final h = AiUiTestHost();
    await h.mount(
        tester, Scaffold(body: AiFirstGuide(onFinished: () => finished++)));
    for (var index = 0; index < 3; index++) {
      await tester.tap(find.image(AssetImage(AiFirstGuide.assets[index])));
      await tester.pumpAndSettle();
      expect(finished, 0);
    }
    final last = find.descendant(
      of: find.byWidgetPredicate((w) => w is Visibility && w.visible),
      matching: find.byType(AiGuideStartButton),
    );
    await tester.tap(last);
    expect(finished, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape guide remains usable with safe insets and large text',
      (tester) async {
    var finished = false;
    final h = AiUiTestHost(
        size: const Size(812, 375),
        textScale: 2,
        padding: const EdgeInsets.fromLTRB(44, 24, 44, 21),
        disableAnimations: true);
    await h.mount(tester,
        Scaffold(body: AiFirstGuide(onFinished: () => finished = true)));
    for (var index = 0; index < 3; index++) {
      await tester.tap(find.image(AssetImage(AiFirstGuide.assets[index])));
      await tester.pumpAndSettle();
    }
    final button = find.descendant(
        of: find.byWidgetPredicate((w) => w is Visibility && w.visible),
        matching: find.byType(AiGuideStartButton));
    await tester.ensureVisible(button);
    await tester.tap(button);
    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool chips select and deselect without sending input',
      (tester) async {
    final h = AiUiTestHost();
    String? selected;
    final selections = <String>[];
    await h.mount(
        tester,
        h.scaffold((context) => StatefulBuilder(
              builder: (context, update) => AiQuickChipBar(
                  dark: false,
                  i18n: AiAssistantI18n.of(context),
                  selectedId: selected,
                  onSelected: (tool) => update(() {
                        selections.add(tool);
                        selected = selected == tool ? null : tool;
                      })),
            )));
    await tester.tap(find.text('总结聊天'));
    await tester.pump();
    expect(selected, 'summarize');
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(selected, isNull);
    await tester.drag(find.byType(AiQuickChipBar), const Offset(-240, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('写文案'));
    expect(selections, ['summarize', 'summarize', 'write']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'composer preserves typed input and delegates add media send stop',
      (tester) async {
    final h = AiUiTestHost();
    final input = TextEditingController();
    final focus = FocusNode();
    addTearDown(input.dispose);
    addTearDown(focus.dispose);
    var replying = false;
    final calls = <String>[];
    await h.mount(
        tester,
        h.scaffold((context) => StatefulBuilder(
              builder: (context, update) => Padding(
                padding: const EdgeInsets.all(12),
                child: AiInputBar(
                    dark: false,
                    hint: '向 99ChatAI 提问',
                    controller: input,
                    focusNode: focus,
                    replying: replying,
                    onAdd: () => calls.add('add'),
                    onImage: () => calls.add('image'),
                    onAttach: () => calls.add('file'),
                    onSubmit: () => update(() {
                          calls.add(input.text);
                          replying = true;
                        }),
                    onStop: () => calls.add('stop')),
              ),
            )));
    await tester.enterText(find.byType(TextField), '保留我的问题');
    for (final icon in [
      Icons.add,
      Icons.image_outlined,
      Icons.description_outlined,
      Icons.send_rounded,
      Icons.stop_rounded
    ]) {
      await tester.tap(find.byIcon(icon));
      await tester.pump();
    }
    expect(calls, ['add', 'image', 'file', '保留我的问题', 'stop']);
    expect(input.text, '保留我的问题');
    expect(tester.takeException(), isNull);
  });

  testWidgets('attachment menu returns selected action and cancellation',
      (tester) async {
    final h = AiUiTestHost();
    final results = <String?>[];
    await h.mount(
        tester,
        h.scaffold((context) => Column(children: [
              TextButton(
                  onPressed: () async =>
                      results.add(await AiMoreSheet.show(context)),
                  child: const Text('附件')),
              TextButton(
                  onPressed: () async =>
                      results.add(await AiMoreSheet.overflow(context)),
                  child: const Text('更多')),
              TextButton(
                  onPressed: () async =>
                      results.add(await AiMoreSheet.copy(context)),
                  child: const Text('消息')),
            ])));
    for (final entry in [
      ('附件', '好友名片'),
      ('附件', '取消'),
      ('更多', '清空记录'),
      ('消息', '复制')
    ]) {
      await tester.tap(find.text(entry.$1));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      await tester.tap(find.text(entry.$2));
      await tester.pumpAndSettle();
    }
    expect(results, ['friend', null, 'clear', 'copy']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('draft removal targets its item and displays in-memory images',
      (tester) async {
    final h = AiUiTestHost();
    final drafts = <AiAssistantDraftItem>[
      const AiAssistantDraftItem.card(aiTestCard),
      const AiAssistantDraftItem.file(aiTestFile),
      AiAssistantDraftItem.file(AiAssistantFileRef(
          name: '图片.jpg',
          sizeLabel: '1 KB',
          kind: AiAssistantFileKind.image,
          bytes: aiTestImage)),
    ];
    await h.mount(
        tester,
        h.scaffold((context) => StatefulBuilder(
              builder: (context, update) => AiDraftBar(
                  dark: false,
                  i18n: AiAssistantI18n.of(context),
                  drafts: drafts,
                  onRemove: (index) => update(() => drafts.removeAt(index))),
            )));
    await tester.tap(find.byIcon(Icons.close_rounded).first);
    await tester.pumpAndSettle();
    expect(drafts.map((item) => item.file?.name), ['项目计划.pdf', '图片.jpg']);
    expect(find.image(MemoryImage(aiTestImage)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large-text user message opens file and card and copies on hold',
      (tester) async {
    final h = AiUiTestHost(textScale: 2, dark: true);
    final calls = <String>[];
    await h.mount(
        tester,
        h.scaffold((context) => Padding(
              padding: const EdgeInsets.all(16),
              child: AiUserBubble(
                  dark: true,
                  faceUrl: '',
                  showName: '我',
                  ownerId: 'test',
                  message: const AiAssistantMessage(
                      role: AiAssistantRole.user,
                      time: '14:30',
                      text: '请分析这个文件',
                      files: [
                        aiTestFile
                      ],
                      cards: [
                        AiAssistantCardRef(
                            kind: AiAssistantCardKind.friend,
                            id: 'long-name',
                            name: '需要保持可读的长名字与好友名片显示内容'),
                      ]),
                  fileCache: const {},
                  onCardTap: (_) => calls.add('card'),
                  onFileTap: (_) => calls.add('file'),
                  onLongPress: () => calls.add('hold')),
            )));
    await tester.tap(find.byType(AiUserCardRow));
    await tester.tap(find.byType(AiUserFileRow));
    await tester.longPress(find.text('请分析这个文件'));
    expect(calls, ['card', 'file', 'hold']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'assistant output cards render actual data and open original file',
      (tester) async {
    final h = AiUiTestHost(textScale: 2);
    var opened = 0;
    const outputs = [
      AiAssistantMessage(
          role: AiAssistantRole.assistant,
          time: '14:30',
          text: '**这是回复正文**\n\n- 第一项',
          outputKind: AiAssistantOutputKind.text),
      AiAssistantMessage(
          role: AiAssistantRole.assistant,
          time: '14:30',
          outputKind: AiAssistantOutputKind.summary,
          summary: AiAssistantSummaryData(
              title: '这是一段较长的讨论总结标题',
              meta: '3 个重点',
              items: ['确认目标', '安排人员'],
              footer: '继续讨论')),
      AiAssistantMessage(
          role: AiAssistantRole.assistant,
          time: '14:30',
          outputKind: AiAssistantOutputKind.code,
          code: AiAssistantCodeData(
              language: 'dart', source: 'final ready = true;')),
      AiAssistantMessage(
          role: AiAssistantRole.assistant,
          time: '14:30',
          outputKind: AiAssistantOutputKind.fileAnalysis,
          analysis: AiAssistantAnalysisData(
              fileName: '计划.pdf', sizeLabel: '128 KB', bullets: ['检查里程碑'])),
    ];
    for (final message in outputs) {
      await h.mount(
          tester,
          h.scaffold((context) => SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: AiAssistantBubble(
                    dark: false,
                    i18n: AiAssistantI18n.of(context),
                    message: message,
                    onComingSoon: (_) => fail('real callback must win'),
                    fileCache: const {},
                    onNeedFile: (_) {},
                    onViewOriginal: () => opened++),
              )));
      if (message.outputKind == AiAssistantOutputKind.fileAnalysis) {
        await tester.tap(find.text('查看原文件'));
      }
      expect(tester.takeException(), isNull);
    }
    expect(opened, 1);
  });

  testWidgets('Markdown requests missing private image then opens cached bytes',
      (tester) async {
    final h = AiUiTestHost();
    final requests = <String>[];
    final opened = <String>[];
    const raw = '/ai-assistant/api/v1/chat/files/image-1';
    final waiting = h.scaffold((context) => AiAssistantMarkdown(
        dark: false,
        text: '![图]($raw)',
        fileCache: const {},
        onNeedFile: requests.add));
    await h.mount(tester, waiting, settle: false);
    expect(requests, contains('image-1'));
    await h.mount(
        tester,
        h.scaffold((context) => AiAssistantMarkdown(
            dark: false,
            text: '![图]($raw)',
            fileCache: {'image-1': aiTestImage},
            onNeedFile: requests.add,
            onImageTap: opened.add)));
    await tester.tap(find.image(MemoryImage(aiTestImage)));
    expect(opened, [raw]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Markdown refreshes equal-size cache eviction and same-ID bytes replacement',
      (tester) async {
    final h = AiUiTestHost();
    final cache = {'stale-image': aiTestImage};
    final requests = <String>[];
    const raw = '/ai-assistant/api/v1/chat/files/image-1';
    late StateSetter update;
    await h.mount(
        tester,
        h.scaffold((context) => StatefulBuilder(builder: (context, setState) {
              update = setState;
              return AiAssistantMarkdown(
                  dark: false,
                  text: '![图]($raw)',
                  fileCache: cache,
                  onNeedFile: requests.add);
            })),
        settle: false);
    expect(requests, contains('image-1'));
    await tester.runAsync(() => precacheImage(MemoryImage(aiTestImage),
        tester.element(find.byType(AiAssistantMarkdown))));
    update(() {
      cache.remove('stale-image');
      cache['image-1'] = aiTestImage;
    });
    await tester.pumpAndSettle();
    expect(cache.length, 1);
    expect(find.image(MemoryImage(aiTestImage)), findsOneWidget);
    final firstHeight =
        tester.getSize(find.image(MemoryImage(aiTestImage))).height;

    final replacement = (await tester
        .runAsync(() => File('assets/ai/99chat.webp').readAsBytes()))!;
    await tester.runAsync(() => precacheImage(MemoryImage(replacement),
        tester.element(find.byType(AiAssistantMarkdown))));
    update(() => cache['image-1'] = replacement);
    await tester.pumpAndSettle();
    expect(cache.length, 1);
    expect(find.image(MemoryImage(replacement)), findsOneWidget);
    expect(find.image(MemoryImage(aiTestImage)), findsNothing);
    expect(tester.getSize(find.image(MemoryImage(replacement))).height,
        greaterThan(firstHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reduced motion keeps thinking feedback without a repeating ticker',
      (tester) async {
    final h = AiUiTestHost(disableAnimations: true);
    await h.mount(
        tester,
        h.scaffold((context) =>
            AiThinkingCard(dark: false, i18n: AiAssistantI18n.of(context))));
    expect(find.text('思考中'), findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });
}
