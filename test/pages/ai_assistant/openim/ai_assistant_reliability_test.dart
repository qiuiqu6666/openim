import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/ai_assistant/ai_assistant_chat_page.dart';
import 'package:openim/pages/ai_assistant/navigation/ai_assistant_header.dart';
import 'package:openim/pages/ai_assistant/presentation/composer/ai_composer.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_state.dart';
import 'package:openim/pages/ai_assistant/streaming/assistant_stream_chunk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../presentation/support/ai_ui_test_host.dart';
import 'support/ai_openim_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await initializeAiUiTests();
    PackageInfo.setMockInitialValues(
        appName: '99Chat',
        packageName: 'test.openim',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    await Config.init(() {});
  });

  testWidgets('stream deadlines are independent and late deltas resume',
      (tester) async {
    final state =
        AssistantStreamState(replyTimeout: const Duration(seconds: 10));
    state.accept(const AssistantStreamChunk(
        streamID: 'first', index: 0, text: 'A', end: false));
    await tester.pump(const Duration(seconds: 6));
    state.accept(const AssistantStreamChunk(
        streamID: 'second', index: 0, text: 'B', end: false));
    await tester.pump(const Duration(seconds: 5));
    expect(state.snapshots.first.timedOut, isTrue);
    expect(state.snapshots.last.timedOut, isFalse);
    state.accept(const AssistantStreamChunk(
        streamID: 'first', index: 1, text: 'C', end: false));
    expect(state.snapshots.first.timedOut, isFalse);
    expect(state.snapshots.first.text, 'AC');
    state.markFinal('first');
    state.clear();
    await tester.pump(const Duration(seconds: 20));
    expect(state.snapshots, isEmpty);
    state.dispose();
  });

  testWidgets('expired wait displays guidance and clears the replying header',
      (tester) async {
    final fixture = AiOpenimTestFixture();
    await fixture.initialize();
    final logic = fixture.open();
    await tester.idle();
    fixture.histories.single.complete([]);
    await AiUiTestHost(disableAnimations: true)
        .mount(tester, AiAssistantChatPage(logic: logic));
    logic.assistantStreams.beginReply();
    await tester.pump();
    await tester.pump(const Duration(minutes: 3));
    expect(find.text('回复等待较久，你可以继续提问。收到回复后会自动更新。'), findsOneWidget);
    expect(find.text('正在回复…'), findsNothing);
    fixture.im.recvNewMessage(aiOpenimText('late', 'late reply'));
    await tester.pump();
    expect(logic.assistantStreams.snapshots, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('reply waiting expires without discarding late responses',
      (tester) async {
    final state = AssistantStreamState();
    state.beginReply();
    await tester.pump(const Duration(minutes: 30));
    expect(state.snapshots.single.timedOut, isTrue);
    state.receivedReply(aiOpenimText("late", "answer"));
    expect(state.snapshots, isEmpty);
    state.dispose();
  });

  testWidgets('duplicate old message preserves the new reply wait',
      (tester) async {
    final fixture = AiOpenimTestFixture();
    await fixture.initialize();
    final logic = fixture.open();
    await tester.idle();
    final old = aiOpenimText('old-reply', 'old answer');
    fixture.histories.single.complete([old]);
    await AiUiTestHost(disableAnimations: true)
        .mount(tester, AiAssistantChatPage(logic: logic));
    expect(logic.messageList.length, 1);
    logic.assistantStreams.beginReply();
    expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
    fixture.im.recvNewMessage(aiOpenimText('old-reply', 'old answer'));
    await tester.pump();
    expect(logic.messageList.length, 1);
    expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('search explicitly identifies its loaded window', (tester) async {
    final fixture = AiOpenimTestFixture();
    await fixture.initialize();
    final logic = fixture.open();
    await tester.idle();
    fixture.histories.single
        .complete([aiOpenimText('recent', 'recent answer')]);
    await AiUiTestHost(disableAnimations: true)
        .mount(tester, AiAssistantChatPage(logic: logic));
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    final field = find.descendant(
        of: find.byType(AiAssistantHeader), matching: find.byType(TextField));
    final count = fixture.nativeCalls.length;
    await tester.enterText(field, 'older answer');
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0/0'), findsOneWidget);
    expect(tester.widget<TextField>(field).decoration!.hintText, '查找已加载消息');
    expect(
        fixture.nativeCalls
            .skip(count)
            .where((c) => c.method.toLowerCase().contains('search')),
        isEmpty);
    expect(fixture.histories.length, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('selected tool uses one full-size toggle target', (tester) async {
    final fixture = AiOpenimTestFixture();
    await fixture.initialize();
    final logic = fixture.open();
    await tester.idle();
    fixture.histories.single.complete([]);
    await AiUiTestHost(disableAnimations: true)
        .mount(tester, AiAssistantChatPage(logic: logic));
    await tester.tap(find.text('生成图片'));
    await tester.pump();
    final chip = find
        .ancestor(of: find.text('生成图片'), matching: find.byType(InkWell))
        .first;
    expect(tester.getSize(chip).height, greaterThanOrEqualTo(48));
    final close = find.descendant(
        of: find.byType(AiQuickChipBar),
        matching: find.byIcon(Icons.close_rounded));
    expect(find.ancestor(of: close, matching: find.byType(InkWell)),
        findsOneWidget);
    await tester.tap(chip);
    await tester.pump();
    expect(close, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('multiline quoted draft fits small phone with keyboard',
      (tester) async {
    final fixture = AiOpenimTestFixture();
    await fixture.initialize();
    final logic = fixture.open();
    await tester.idle();
    final old = aiOpenimText('quoted', '这是一条需要继续分析的较长消息内容');
    fixture.histories.single.complete([old]);
    await AiUiTestHost(
            size: const Size(320, 568),
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewInsets: const EdgeInsets.only(bottom: 210),
            textScale: 2,
            disableAnimations: true)
        .mount(tester, AiAssistantChatPage(logic: logic));
    logic.replyToMessage(old);
    await tester.pump();
    await tester.enterText(find.byType(TextField), '第一行\n第二行\n第三行\n第四行');
    await tester.pump();
    final error = tester.takeException();
    expect(error, isNull);
    expect(find.byIcon(Icons.send_rounded).hitTestable(), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await fixture.dispose();
    await tester.pump(const Duration(milliseconds: 600));
  });
}
