import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/ai_assistant/ai_assistant_chat_page.dart';
import 'package:openim/pages/ai_assistant/presentation/ai_assistant_widgets.dart';
import 'package:openim/pages/ai_assistant/presentation/messages/ai_assistant_stream_tile.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../presentation/support/ai_ui_test_host.dart';
import 'support/ai_openim_preview.dart';
import 'support/ai_openim_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AiOpenimTestFixture fixture;
  setUpAll(() async {
    await initializeAiUiTests();
    PackageInfo.setMockInitialValues(
        appName: '99Chat',
        packageName: 'test.openim',
        version: '1',
        buildNumber: '1',
        buildSignature: '');
    // The shared SDK sender requires Config.offlinePushInfo's app name.
    await Config.init(() {});
    if (aiPreviewDirectory.isNotEmpty) await loadAiPreviewFonts();
  });
  setUp(() async {
    fixture = AiOpenimTestFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    await dismissAiUiTestLoading();
    await fixture.dispose();
  });

  Future<ChatLogic> mount(WidgetTester tester,
      {bool dark = false, AiUiTestHost? host}) async {
    final logic = fixture.open();
    await tester.idle();
    fixture.histories.last.complete([]);
    await (host ?? AiUiTestHost(dark: dark, disableAnimations: true))
        .mount(tester, AiAssistantChatPage(logic: logic));
    return logic;
  }

  Future<void> flush(WidgetTester tester) async {
    // Waiting feedback may animate indefinitely, so never settle while pending.
    for (var frame = 0; frame < 4; frame++) {
      await tester.pump();
    }
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await flush(tester);
  }

  Finder previewBubble() => find.descendant(
      of: find.byType(AiAssistantStreamTile),
      matching: find.byType(ChatItemContainer));

  Finder waitingText() => find.descendant(
      of: find.byType(AiAssistantStreamTile), matching: find.text('正在回复…'));

  Finder textContaining(String text) => find.byWidgetPredicate((widget) =>
      widget is RichText && widget.text.toPlainText().contains(text));

  void waitTest(String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        for (final gate in [
          fixture.createTextMessageGate,
          fixture.sendMessageGate,
        ]) {
          if (gate != null && !gate.isCompleted) gate.complete();
        }
        // tearDown runs after widget timer invariants: dismiss error toasts now.
        await dismissAiUiTestLoading();
        await tester.pumpWidget(const SizedBox.shrink());
        for (final logic in fixture.controllers.reversed) {
          if (!logic.isClosed) logic.onDelete();
        }
        for (final history in [
          ...fixture.histories,
          ...fixture.newerHistories
        ]) {
          history.complete([]);
        }
        await tester.pump(const Duration(milliseconds: 600));
      }
    });
  }

  for (final dark in [false, true]) {
    waitTest(
        'send immediately shows one waiting bubble before SDK creation ($dark)',
        (tester) async {
      final createGate = fixture.createTextMessageGate = Completer<void>();
      final sendGate = fixture.sendMessageGate = Completer<void>();
      final host = AiUiTestHost(
          dark: dark,
          previewFont: aiPreviewDirectory.isNotEmpty,
          disableAnimations: true);
      final logic = await mount(tester, host: host);
      await tester.enterText(find.byType(TextField), '请帮我整理下一步安排');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();

      expect(waitingText(), findsOneWidget,
          reason: 'The first frame must not depend on an SDK response.');
      expect(previewBubble(), findsOneWidget);
      expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
      expect(logic.assistantStreams.snapshots.single.text, isEmpty);
      final waitingID = tester.widget<ChatItemContainer>(previewBubble()).id;
      expect(logic.messageList, isEmpty,
          reason: 'No fake assistant message belongs in the SDK history.');
      expect(logic.scrollingCacheMessageList, isEmpty);
      expect(fixture.nativeCalls.where((call) => call.method == 'sendMessage'),
          isEmpty);
      expect(ChatHistoryCache.read('self', aiOpenimConversationID), isEmpty);
      await exportAiOpenimPreview(tester, host, 'pending');

      createGate.complete();
      await flush(tester);
      expect(fixture.nativeCalls.where((call) => call.method == 'sendMessage'),
          hasLength(1));
      expect(logic.messageList, hasLength(1));
      expect(logic.messageList.single.sendID, 'self');
      expect(waitingText(), findsOneWidget);

      sendGate.complete();
      await flush(tester);
      expect(logic.messageList.single.status, MessageStatus.succeeded);
      expect(logic.inputCtrl.text, isEmpty);
      expect(waitingText(), findsOneWidget,
          reason: 'SDK delivery acknowledgement is not an AI reply.');

      fixture.im.recvNewMessage(aiOpenimTyping('typing-while-waiting'));
      await tester.pump();
      expect(waitingText(), findsOneWidget);
      // A legacy typing card must not be rendered outside the pending bubble.
      final nestedThinkingCards = find.descendant(
          of: find.byType(AiAssistantStreamTile),
          matching: find.byType(AiThinkingCard));
      expect(find.byType(AiThinkingCard).evaluate().length,
          nestedThinkingCards.evaluate().length);

      fixture.im.recvNewMessage(aiOpenimStreamFragment('first-fragment',
          streamID: 'live-reply', index: 0, text: '已整理出第一项安排'));
      await flush(tester);
      expect(waitingText(), findsNothing);
      expect(textContaining('已整理出第一项安排'), findsOneWidget);
      expect(logic.assistantStreams.snapshots.single.waiting, isFalse);
      expect(tester.widget<ChatItemContainer>(previewBubble()).id, waitingID,
          reason: 'The first delta updates the existing reply bubble.');
      expect(logic.messageList, hasLength(1));

      fixture.im.recvNewMessage(aiOpenimStreamFinal(
          'durable-final', '完整回复已经保存。', 'live-reply',
          time: 200));
      await flush(tester);
      expect(find.byType(AiAssistantStreamTile), findsNothing);
      expect(logic.assistantStreams.snapshots, isEmpty);
      expect(textContaining('完整回复已经保存。'), findsOneWidget);
      expect(textContaining('已整理出第一项安排'), findsNothing);
      expect(logic.messageList.map((message) => message.clientMsgID),
          ['sent-1', 'durable-final']);
      expect(
          logic.messageList.where((message) => message.sendID == 'assistant'),
          hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  waitTest('dated window feedback does not wait for slow latest SDK history',
      (tester) async {
    final logic = await mount(tester);
    final target = aiOpenimText('dated-target', '仍在阅读的日期正文', time: 100);
    final jump = logic.jumpToDateMessage(target);
    await flush(tester);
    fixture.histories.last.complete([target], isEnd: false);
    fixture.newerHistories.single.complete([target], isEnd: false);
    await tester.pumpAndSettle();
    expect(await jump, isTrue);
    expect(logic.viewingHistory.value, isTrue);
    expect(logic.bufferingLiveMessages, isTrue);

    final createGate = fixture.createTextMessageGate = Completer<void>();
    final sendGate = fixture.sendMessageGate = Completer<void>();
    final historyCount = fixture.histories.length;
    await tester.enterText(find.byType(TextField), '在日期窗口里继续提问');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(waitingText(), findsOneWidget,
        reason:
            'SDK creation and latest-history fetch are both still pending.');
    expect(previewBubble(), findsOneWidget);
    final waitingID = tester.widget<ChatItemContainer>(previewBubble()).id;
    expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
    expect(logic.messageList.map((message) => message.clientMsgID),
        ['dated-target']);
    await flush(tester);
    expect(fixture.histories, hasLength(historyCount + 1));
    final latestHistory = fixture.histories.last;
    expect(latestHistory.result.isCompleted, isFalse);
    expect(logic.bufferingLiveMessages, isTrue);

    createGate.complete();
    await flush(tester);
    expect(fixture.nativeCalls.where((call) => call.method == 'sendMessage'),
        hasLength(1));
    sendGate.complete();
    await flush(tester);
    expect(latestHistory.result.isCompleted, isFalse);
    fixture.im.recvNewMessage(aiOpenimStreamFragment('dated-first-fragment',
        streamID: 'dated-active-reply', index: 0, text: '最新历史返回前已显示首段正文'));
    await flush(tester);
    expect(logic.bufferingLiveMessages, isTrue);
    expect(waitingText(), findsNothing);
    expect(previewBubble(), findsOneWidget);
    expect(tester.widget<ChatItemContainer>(previewBubble()).id, waitingID);
    expect(textContaining('最新历史返回前已显示首段正文'), findsOneWidget);
    expect(
        logic.messageList
            .where((message) => message.clientMsgID == 'dated-first-fragment'),
        isEmpty);

    latestHistory.complete(List<Message>.of(logic.messageList));
    await flush(tester);
    expect(logic.viewingHistory.value, isFalse);
    expect(logic.bufferingLiveMessages, isFalse);
    expect(previewBubble(), findsOneWidget,
        reason: 'Moving feedback into the latest list must not duplicate it.');
    expect(tester.widget<ChatItemContainer>(previewBubble()).id, waitingID);
    fixture.im.recvNewMessage(aiOpenimStreamFinal(
        'dated-durable-reply', '日期窗口提问的完整回复', 'dated-active-reply',
        time: 1030));
    await flush(tester);
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(
        logic.messageList
            .where((message) => message.clientMsgID == 'dated-durable-reply'),
        hasLength(1));
    expect(textContaining('日期窗口提问的完整回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  waitTest('prepared SDK delivery shows waiting without using the AI composer',
      (tester) async {
    final gate = fixture.sendMessageGate = Completer<void>();
    final logic = await mount(tester);
    final message =
        aiOpenimText('prepared-delivery', '重试或附件共享发送', outgoing: true)
          ..status = MessageStatus.sending;
    final delivery = logic.sendPreparedMessage(message);
    await flush(tester);
    expect(fixture.nativeCalls.where((call) => call.method == 'sendMessage'),
        hasLength(1));
    expect(waitingText(), findsOneWidget);
    expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
    expect(logic.messageList.single.clientMsgID, 'prepared-delivery');
    expect(logic.messageList.single.sendID, 'self');

    gate.complete();
    await delivery;
    await flush(tester);
    expect(logic.messageList.single.status, MessageStatus.succeeded);
    expect(waitingText(), findsOneWidget,
        reason: 'A shared delivery acknowledgement must keep reply feedback.');
    fixture.im
        .recvNewMessage(aiOpenimText('prepared-result', '共享发送的回复', time: 200));
    await flush(tester);
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(logic.messageList.map((message) => message.clientMsgID),
        ['prepared-delivery', 'prepared-result']);
    expect(textContaining('共享发送的回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  waitTest('prepared SDK delivery failure removes its waiting feedback',
      (tester) async {
    final gate = fixture.sendMessageGate = Completer<void>();
    final logic = await mount(tester);
    fixture.failNextSend = true;
    final message = aiOpenimText('prepared-failure', '共享发送失败', outgoing: true)
      ..status = MessageStatus.sending;
    final delivery = logic.sendPreparedMessage(message);
    await flush(tester);
    expect(waitingText(), findsOneWidget);
    expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
    gate.complete();
    await delivery;
    await flush(tester);
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(logic.messageList.single.clientMsgID, 'prepared-failure');
    expect(logic.messageList.single.status, MessageStatus.failed);
    expect(logic.messageList.single.sendID, 'self');
    expect(tester.takeException(), isNull);
  });

  waitTest(
      'send failure removes waiting and keeps failed row and editable draft',
      (tester) async {
    final logic = await mount(tester);
    fixture.failNextSend = true;
    await send(tester, '网络失败后保留这条问题');
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(logic.messageList.single.status, MessageStatus.failed);
    expect(logic.messageList.single.textElem?.content, '网络失败后保留这条问题');
    expect(logic.inputCtrl.text, '网络失败后保留这条问题');
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });

  waitTest('SDK message creation failure cancels only the local waiting row',
      (tester) async {
    final gate = fixture.createTextMessageGate = Completer<void>();
    final logic = await mount(tester);
    await send(tester, '创建消息失败后仍可重新发送');
    expect(waitingText(), findsOneWidget);
    gate.completeError(PlatformException(code: 'CREATE_FAILED'));
    await flush(tester);
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(logic.messageList, isEmpty);
    expect(logic.inputCtrl.text, '创建消息失败后仍可重新发送');
    expect(fixture.nativeCalls.where((call) => call.method == 'sendMessage'),
        isEmpty);
    expect(tester.takeException(), isNull);
  });

  waitTest('a later failed send preserves a previously successful reply wait',
      (tester) async {
    final logic = await mount(tester);
    await send(tester, '第一条已经发出的请求');
    expect(logic.assistantStreams.snapshots, hasLength(1));
    final previousID = tester.widget<ChatItemContainer>(previewBubble()).id;
    fixture.failNextSend = true;
    await send(tester, '第二条发送失败的请求');
    expect(logic.assistantStreams.snapshots, hasLength(1));
    expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
    expect(tester.widget<ChatItemContainer>(previewBubble()).id, previousID);
    expect(logic.messageList.map((message) => message.status),
        [MessageStatus.succeeded, MessageStatus.failed]);
    expect(logic.inputCtrl.text, '第二条发送失败的请求');
    expect(tester.takeException(), isNull);
  });

  for (final picture in [false, true]) {
    for (final emptyFirst in [false, true]) {
      waitTest(
          'ordinary ${picture ? 'image' : 'text'} reply ends waiting '
          'after empty stream ($emptyFirst)', (tester) async {
        final logic = await mount(tester);
        await send(tester, '直接返回完整结果');
        expect(waitingText(), findsOneWidget);
        if (emptyFirst) {
          fixture.im.recvNewMessage(aiOpenimStreamFragment('empty-first',
              streamID: 'empty-stream', index: 0, text: ''));
          await flush(tester);
          expect(waitingText(), findsOneWidget);
          expect(logic.assistantStreams.snapshots.single.waiting, isTrue);
          expect(logic.assistantStreams.snapshots.single.text, isEmpty);
          expect(logic.messageList.single.clientMsgID, 'sent-1');
        }
        final result = picture
            ? aiOpenimPicture('plain-result')
            : aiOpenimText('plain-result', '直接返回的完整答案');
        result.seq = 200;
        result.sendTime = 1791178400000;
        expect(result.ex, isNull,
            reason: 'Ordinary results need not contain a final stream ID.');
        fixture.im.recvNewMessage(result);
        await flush(tester);
        expect(logic.assistantStreams.snapshots, isEmpty);
        expect(find.byType(AiAssistantStreamTile), findsNothing);
        expect(logic.messageList.map((message) => message.clientMsgID),
            ['sent-1', 'plain-result']);
        expect(logic.messageList.last.contentType,
            picture ? MessageType.picture : MessageType.text);
        expect(
            picture
                ? find.byType(ChatPictureView)
                : textContaining('直接返回的完整答案'),
            findsOneWidget);
        if (emptyFirst) {
          fixture.im.recvNewMessage(aiOpenimStreamFragment('late-empty-stream',
              streamID: 'empty-stream', index: 1, text: '完成后晚到的正文'));
          await flush(tester);
          expect(logic.assistantStreams.snapshots, isEmpty);
          expect(find.byType(AiAssistantStreamTile), findsNothing);
          expect(textContaining('完成后晚到的正文'), findsNothing);
          expect(logic.messageList.map((message) => message.clientMsgID),
              ['sent-1', 'plain-result']);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  waitTest('closed account waiting never appears in the next account route',
      (tester) async {
    final oldLogic = await mount(tester);
    await send(tester, '旧账号还在等待的请求');
    expect(waitingText(), findsOneWidget);
    final oldCallback = fixture.im.publishLocalChatMessage;
    await tester.pumpWidget(const SizedBox.shrink());
    oldLogic.onDelete();
    expect(oldLogic.assistantStreams.snapshots, isEmpty);
    expect(oldLogic.assistantStreams.isDisposed, isTrue);

    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': 'another-account',
      'chatToken': 'another-chat-session',
      'imToken': 'another-im-session',
    }));
    OpenIM.iMManager.userID = 'another-account';
    OpenIM.iMManager.userInfo = UserInfo(userID: 'another-account');
    final nextLogic = await mount(tester);
    oldCallback(aiOpenimText('late-old-account', '旧账号晚到的回复'));
    await flush(tester);
    expect(oldLogic.assistantStreams.snapshots, isEmpty);
    expect(nextLogic.assistantStreams.snapshots, isEmpty);
    expect(nextLogic.messageList, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(textContaining('旧账号晚到的回复'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  waitTest(
      'another interactive official account does not create assistant wait',
      (tester) async {
    final gate = fixture.createTextMessageGate = Completer<void>();
    Get.routing.args = {
      'conversationInfo': ConversationInfo(
        conversationID: 'si_other_official_self',
        userID: 'other-official',
        conversationType: ConversationType.single,
        showName: '其他官方账号',
        ex: '{"accountType":"official"}',
        unreadCount: 0,
        groupAtType: GroupAtType.atNormal,
        isPrivateChat: false,
      ),
    };
    final logic = ChatLogic();
    fixture.controllers.add(logic);
    logic.onInit();
    await tester.idle();
    fixture.histories.single.complete([]);
    await AiUiTestHost(disableAnimations: true)
        .mount(tester, AiAssistantChatPage(logic: logic));
    await send(tester, '普通官方账号的消息');
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(logic.messageList, isEmpty);
    gate.complete();
    await flush(tester);
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(find.byType(AiAssistantStreamTile), findsNothing);
    expect(logic.messageList, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
