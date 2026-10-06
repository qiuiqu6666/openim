import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/ai_assistant_page.dart';
import 'package:openim/pages/ai_assistant/presentation/ai_assistant_widgets.dart';

import 'support/ai_ui_test_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeAiUiTests);
  tearDown(resetAiUiTests);

  testWidgets('unconnected page keeps input and reports service availability',
      (tester) async {
    final c = AiUiTestController();
    addTearDown(c.dispose);
    final h = AiUiTestHost();
    await h.mount(tester, AiAssistantPage(controller: c));
    await tester.tap(find.text('开始新对话'));
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.enterText(find.byType(TextField), '这条问题需要真实服务');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.messages, isEmpty);
    expect(field.controller!.text, '这条问题需要真实服务');
    expect(find.text('AI 服务尚未接入'), findsOneWidget);
    await tester.pumpAndSettle();
    await dismissAiUiTestLoading();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('page guide dismissal reveals working tools and input',
      (tester) async {
    final c = AiUiTestController(guide: true);
    addTearDown(c.dispose);
    final h = AiUiTestHost(disableAnimations: true);
    await h.mount(tester, AiAssistantPage(controller: c));
    for (var index = 0; index < 3; index++) {
      await tester.tap(find.image(AssetImage(AiFirstGuide.assets[index])));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.descendant(
        of: find.byWidgetPredicate((w) => w is Visibility && w.visible),
        matching: find.byType(AiGuideStartButton)));
    await tester.pumpAndSettle();
    expect(c.guideVisible, isFalse);
    await tester.tap(find.text('生成图片'));
    await tester.pump();
    expect(c.selectedTool, 'image');
    expect(
        tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
        '描述你想生成的图片…');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'conversation search counts matches and close restores draft text',
      (tester) async {
    final c = AiUiTestController(initialMessages: aiTestConversation);
    addTearDown(c.dispose);
    final h = AiUiTestHost();
    await h.mount(tester, AiAssistantPage(controller: c));
    await tester.enterText(find.byType(TextField), '尚未发送的草稿');
    await tester.tap(find.byTooltip('搜索此对话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('ai-search-input')), '讨论');
    await tester.pumpAndSettle();
    expect(find.text('1/3'), findsOneWidget);
    await tester.tap(find.byTooltip('下一项'));
    await tester.pumpAndSettle();
    expect(find.text('2/3'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭搜索'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('ai-search-input')), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '尚未发送的草稿');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'overflow cancellation keeps history and clear delegates directly',
      (tester) async {
    final c = AiUiTestController(initialMessages: aiTestConversation);
    addTearDown(c.dispose);
    final h = AiUiTestHost();
    await h.mount(tester, AiAssistantPage(controller: c));
    for (final answer in ['取消', '清空记录']) {
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(c.messages.length, aiTestConversation.length);
      await tester.tap(find.text(answer));
      await tester.pumpAndSettle();
      expect(c.messages.length, answer == '取消' ? aiTestConversation.length : 0);
    }
    expect(find.text('还没有聊天内容'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'page supports keyboard inset large text and landscape safe areas',
      (tester) async {
    for (final layout in [
      (
        size: const Size(375, 812),
        padding: const EdgeInsets.fromLTRB(0, 44, 0, 34),
        keyboard: 300.0
      ),
      (
        size: const Size(812, 375),
        padding: const EdgeInsets.fromLTRB(44, 24, 44, 21),
        keyboard: 0.0
      ),
    ]) {
      final c = AiUiTestController();
      final h = AiUiTestHost(
          size: layout.size,
          padding: layout.padding,
          textScale: 2,
          disableAnimations: true,
          viewInsets: EdgeInsets.only(bottom: layout.keyboard));
      await h.mount(tester, AiAssistantPage(controller: c));
      final composer = tester.getRect(find.byType(AiInputBar));
      expect(composer.bottom,
          lessThanOrEqualTo(layout.size.height - layout.keyboard));
      expect(composer.left, greaterThanOrEqualTo(layout.padding.left));
      expect(composer.right,
          lessThanOrEqualTo(layout.size.width - layout.padding.right));
      await tester.enterText(find.byType(TextField), '大字体仍能输入');
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '大字体仍能输入');
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      final textScaler = editable.textScaler ??
          MediaQuery.textScalerOf(tester.element(find.byType(EditableText)));
      final lineHeight = textScaler.scale(editable.style.fontSize!) *
          (editable.style.height ?? 1);
      expect(tester.getSize(find.byType(EditableText)).height,
          greaterThanOrEqualTo(lineHeight));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    }
  });

  for (final dark in [false, true]) {
    testWidgets('export actual AI page and action surfaces ($dark)',
        (tester) async {
      final oldShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        await tester.runAsync(loadAiPreviewFonts);
        final h = AiUiTestHost(
            dark: dark, previewFont: true, disableAnimations: true);
        final c = AiUiTestController();
        addTearDown(c.dispose);
        Future<void> mountSnapshot() async {
          // Each capture starts with fresh platform layers after popup teardown.
          await tester.pumpWidget(const SizedBox.shrink());
          await h.mount(tester, AiAssistantPage(controller: c));
        }

        await mountSnapshot();
        await h.export(tester, 'empty');

        c.guideVisible = true;
        await mountSnapshot();
        await h.export(tester, 'first-guide');
        await c.dismissGuide();
        await mountSnapshot();

        await tester.tap(find.text('生成图片'));
        await tester.pump();
        await mountSnapshot();
        await h.export(tester, 'tools');
        await mountSnapshot();
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
        await h.export(tester, 'attachments');
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();

        c.selectTool(null);
        c.messages.addAll(aiTestConversation);
        await mountSnapshot();
        await h.export(tester, 'messages');
        expect(tester.takeException(), isNull);
      } finally {
        debugDisableShadows = oldShadows;
      }
    }, skip: aiPreviewDirectory.isEmpty);
  }
}
