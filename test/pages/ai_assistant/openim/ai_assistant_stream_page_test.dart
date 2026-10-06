import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/ai_assistant/ai_assistant_chat_page.dart';
import 'package:openim/pages/ai_assistant/presentation/messages/ai_assistant_stream_tile.dart';
import 'package:openim/pages/chat/chat_logic.dart';
import 'package:openim/services/chat_history_cache.dart';
import 'package:openim_common/openim_common.dart';

import '../presentation/support/ai_ui_test_host.dart';
import 'support/ai_openim_test_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AiOpenimTestFixture fixture;
  setUpAll(initializeAiUiTests);
  setUp(() async {
    fixture = AiOpenimTestFixture();
    await fixture.initialize();
  });
  tearDown(() async {
    await dismissAiUiTestLoading();
    await fixture.dispose();
  });

  Future<ChatLogic> mount(WidgetTester tester,
      {bool dark = false,
      AiUiTestHost? host,
      List<Message> history = const []}) async {
    final logic = fixture.open();
    await tester.idle();
    fixture.histories.single.complete(history);
    await (host ?? AiUiTestHost(dark: dark, disableAnimations: true))
        .mount(tester, AiAssistantChatPage(logic: logic));
    return logic;
  }

  Finder stream(String id) => find.byWidgetPredicate(
      (widget) => widget is AiAssistantStreamTile && widget.streamID == id);
  Finder textContaining(String text) => find.byWidgetPredicate((widget) =>
      widget is RichText && widget.text.toPlainText().contains(text));

  void streamTest(
      String description, Future<void> Function(WidgetTester) body) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final logic in fixture.controllers.reversed) {
          if (!logic.isClosed) logic.onDelete();
        }
        await tester.pump(const Duration(milliseconds: 600));
      }
    });
  }

  for (final dark in [false, true]) {
    streamTest(
        'live stream is visible without persistence or notification ($dark)',
        (tester) async {
      final logic = await mount(tester, dark: dark);
      fixture.im.recvNewMessage(aiOpenimStreamFragment('chunk-0',
          streamID: 'reply-1', index: 0, text: '第一段正在生成'));
      await tester.pump();
      expect(stream('reply-1'), findsOneWidget);
      expect(textContaining('第一段正在生成'), findsWidgets);
      expect(logic.messageList, isEmpty);
      expect(logic.scrollingCacheMessageList, isEmpty);
      expect(logic.newMessages.unseenCount.value, 0);
      expect(fixture.app.notifications, isEmpty);
      expect(find.text('还没有聊天内容'), findsNothing);

      fixture.im.recvNewMessage(aiOpenimStreamFragment('chunk-1',
          streamID: 'reply-1', index: 1, text: '，第二段已到达。', end: true));
      await tester.pump();
      expect(logic.assistantStreams.snapshots.single.text, '第一段正在生成，第二段已到达。');
      expect(logic.assistantStreams.snapshots.single.ended, isTrue);
      expect(stream('reply-1'), findsOneWidget,
          reason:
              'The end flag keeps the preview until the durable reply arrives.');
      expect(fixture.app.notifications, isEmpty);
      await tester.pump(const Duration(milliseconds: 100));
      expect(ChatHistoryCache.read('self', aiOpenimConversationID), isEmpty);

      fixture.im.recvNewMessage(
          aiOpenimStreamFinal('durable-reply', '这是完整回复正文。', 'reply-1'));
      await tester.pump();
      await tester.pump();
      expect(stream('reply-1'), findsNothing);
      expect(logic.assistantStreams.snapshots, isEmpty);
      expect(textContaining('这是完整回复正文。'), findsWidgets);
      expect(textContaining('第一段正在生成'), findsNothing);
      expect(logic.messageList.single.clientMsgID, 'durable-reply');
      expect(logic.messageList.single.contentType, MessageType.text);
      expect(fixture.app.notifications.map((message) => message.clientMsgID),
          ['durable-reply']);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          ChatHistoryCache.read('self', aiOpenimConversationID)
              .map((message) => message.clientMsgID),
          ['durable-reply']);
      expect(tester.takeException(), isNull);
    });
  }

  streamTest(
      'out-of-order duplicate fragments and concurrent replies stay separate',
      (tester) async {
    final logic = await mount(tester);
    fixture.im.recvNewMessage(
        aiOpenimStreamFragment('one-1', streamID: 'one', index: 1, text: '世界'));
    fixture.im.recvNewMessage(aiOpenimStreamFragment('two-0',
        streamID: 'two', index: 0, text: '另一条回复'));
    fixture.im.recvNewMessage(aiOpenimStreamFragment('one-0',
        streamID: 'one', index: 0, text: '你好，'));
    fixture.im.recvNewMessage(aiOpenimStreamFragment('one-1-replay',
        streamID: 'one', index: 1, text: '世界'));
    fixture.im.recvNewMessage(aiOpenimStreamFragment('one-2',
        streamID: 'one', index: 2, text: '。', end: true));
    await tester.pump();
    final texts = {
      for (final snapshot in logic.assistantStreams.snapshots)
        snapshot.streamID: snapshot.text,
    };
    expect(texts, {'one': '你好，世界。', 'two': '另一条回复'});
    expect(stream('one'), findsOneWidget);
    expect(stream('two'), findsOneWidget);
    expect(tester.getTopLeft(stream('one')).dy,
        lessThan(tester.getTopLeft(stream('two')).dy));
    expect(logic.messageList, isEmpty);
    expect(fixture.app.notifications, isEmpty);

    fixture.im
        .recvNewMessage(aiOpenimStreamFinal('final-two', '第二条完整回复', 'two'));
    await tester.pumpAndSettle();
    expect(stream('two'), findsNothing);
    expect(stream('one'), findsOneWidget);
    expect(logic.assistantStreams.snapshots.single.streamID, 'one');
    expect(tester.getTopLeft(stream('one')).dy,
        lessThan(tester.getTopLeft(textContaining('第二条完整回复').first).dy),
        reason: 'Replacing a later reply keeps the earlier stream above it.');
    fixture.im.recvNewMessage(aiOpenimStreamFragment('late-two',
        streamID: 'two', index: 1, text: '晚到的片段'));
    await tester.pump();
    expect(stream('two'), findsNothing,
        reason:
            'A completed stream must not reappear from a late online packet.');
    expect(
        logic.messageList.map((message) => message.clientMsgID), ['final-two']);
    fixture.im
        .recvNewMessage(aiOpenimStreamFinal('final-one', '第一条完整回复', 'one'));
    await tester.pumpAndSettle();
    expect(stream('one'), findsNothing);
    expect(stream('two'), findsNothing);
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(logic.messageList.map((message) => message.clientMsgID),
        ['final-two', 'final-one']);
    expect(textContaining('第一条完整回复'), findsOneWidget);
    expect(textContaining('第二条完整回复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  streamTest(
      'a final reply with no received fragments stays a normal history message',
      (tester) async {
    final finalMessage =
        aiOpenimStreamFinal('history-final', '换设备后仍可读到正文。', 'old');
    final logic = await mount(tester, history: [finalMessage]);
    expect(textContaining('换设备后仍可读到正文。'), findsWidgets);
    expect(logic.messageList.single.clientMsgID, 'history-final');
    expect(logic.assistantStreams.snapshots, isEmpty);
    fixture.im
        .recvNewMessage(aiOpenimStreamFinal('new-final', '直接收到完整回复。', 'new'));
    await tester.pump();
    expect(textContaining('直接收到完整回复。'), findsWidgets);
    expect(logic.messageList.map((message) => message.clientMsgID),
        ['history-final', 'new-final']);
    expect(logic.assistantStreams.snapshots, isEmpty);
    fixture.im.recvNewMessage(aiOpenimStreamFragment('old-late',
        streamID: 'old', index: 0, text: '已保存回复的过期片段'));
    fixture.im.recvNewMessage(aiOpenimStreamFragment('new-late',
        streamID: 'new', index: 0, text: '完整回复之后才到的片段'));
    await tester.pump();
    expect(logic.assistantStreams.snapshots, isEmpty,
        reason:
            'Both SDK history and live final messages prevent stale previews.');
    expect(stream('old'), findsNothing);
    expect(stream('new'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  streamTest(
      'scrolling in history never counts online fragments as unread arrivals',
      (tester) async {
    final logic = await mount(tester,
        history: List.generate(
            30,
            (index) => aiOpenimText('history-$index', '已经保存的第 $index 条聊天',
                time: index + 1)));
    logic.scrollController.jumpTo(160);
    await tester.pump();
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    final offset = logic.scrollController.offset;
    fixture.im.recvNewMessage(aiOpenimStreamFragment('away-chunk',
        streamID: 'away', index: 0, text: '只有在线预览的内容'));
    await tester.pump();
    expect(logic.messageList, hasLength(30));
    expect(logic.newMessages.unseenCount.value, 0);
    expect(logic.newMessages.awayFromLatest.value, isTrue);
    expect(logic.scrollController.offset, offset,
        reason: 'A preview must not interrupt reading older chat messages.');
    expect(fixture.app.notifications, isEmpty);
    fixture.im.recvNewMessage(
        aiOpenimStreamFinal('durable-arrival', '保存后的完整回复才是一条新消息。', 'away'));
    await tester.pump();
    expect(logic.messageList, hasLength(31));
    expect(logic.newMessages.unseenCount.value, 1);
    expect(logic.scrollController.offset, offset);
    expect(tester.takeException(), isNull);
  });

  streamTest(
      'closing rejects saved SDK callbacks and never caches stream previews',
      (tester) async {
    final logic = await mount(tester,
        history: [aiOpenimText('durable-history', '已经保存的聊天正文')]);
    fixture.im.recvNewMessage(aiOpenimStreamFragment('active-chunk',
        streamID: 'active', index: 0, text: '关闭前的片段'));
    await tester.pump();
    expect(stream('active'), findsOneWidget);
    final ownedCallback = fixture.im.onRecvNewMessage!;
    await tester.pumpWidget(const SizedBox.shrink());
    logic.onDelete();
    final closedSnapshots = [
      for (final snapshot in logic.assistantStreams.snapshots)
        (snapshot.streamID, snapshot.text),
    ];
    expect(fixture.im.onRecvNewMessage, isNull);
    ownedCallback(aiOpenimStreamFragment('late-chunk',
        streamID: 'active', index: 1, text: '关闭后不应显示'));
    ownedCallback(aiOpenimStreamFinal('late-final', '关闭后不应写入', 'active'));
    await tester.pump();
    expect([
      for (final snapshot in logic.assistantStreams.snapshots)
        (snapshot.streamID, snapshot.text),
    ], closedSnapshots);
    expect(logic.messageList.map((message) => message.clientMsgID),
        ['durable-history']);
    expect(
        ChatHistoryCache.read('self', aiOpenimConversationID)
            .map((message) => message.clientMsgID),
        ['durable-history']);
    expect(tester.takeException(), isNull);
  });

  streamTest(
      'malformed online stream packets do not become saved custom messages',
      (tester) async {
    final logic = await mount(tester);
    final malformed = aiOpenimStreamFragment('invalid',
        streamID: 'ignored', index: 0, text: '不能作为普通消息保存');
    malformed.customElem!.data = '{broken-json';
    fixture.im.recvNewMessage(malformed);
    await tester.pump();
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(logic.messageList, isEmpty);
    expect(fixture.app.notifications, isEmpty);
    expect(tester.takeException(), isNull);
  });

  streamTest(
      'growing replies follow latest and preserve a history reader anchor',
      (tester) async {
    Finder source(String id) => find.byWidgetPredicate((widget) =>
        widget is ChatMessageContentAnchor && widget.messageID == id);
    final growth = '${List.filled(36, '连续增长的回复需要保持当前正在阅读的位置。').join('\n\n')}'
        '\n\n流式回复目前的末尾。';
    for (final dark in [false, true]) {
      final followingID = 'following-$dark';
      final readingID = 'reading-$dark';
      final logic = await mount(tester,
          host: AiUiTestHost(
              dark: dark,
              size: const Size(320, 568),
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
              textScale: 2,
              disableAnimations: true),
          history: List.generate(
              30,
              (index) => aiOpenimText('geometry-$dark-$index', '保留的聊天正文 $index',
                  time: index + 1)));
      fixture.im.recvNewMessage(aiOpenimStreamFragment('following-0',
          streamID: followingID, index: 0, text: '当前最新回复。\n\n'));
      await tester.pumpAndSettle();
      fixture.im.recvNewMessage(aiOpenimStreamFragment('following-1',
          streamID: followingID, index: 1, text: growth));
      await tester.pumpAndSettle();
      final viewport = tester.getRect(find.byType(ChatListView));
      expect(logic.scrollController.offset,
          closeTo(logic.scrollController.position.minScrollExtent, 1));
      expect(stream(followingID), findsOneWidget);
      final streamRect =
          tester.getRect(source('assistant-stream:$followingID'));
      expect(streamRect.overlaps(viewport), isTrue);
      expect(streamRect.bottom, lessThanOrEqualTo(viewport.bottom + 1));
      expect(
          tester.getRect(textContaining('流式回复目前的末尾。').last).overlaps(viewport),
          isTrue,
          reason: 'Following latest must paint the newest generated text.');
      fixture.im.recvNewMessage(
          aiOpenimStreamFinal('geometry-final-$dark', '本轮完整回复', followingID));
      await tester.pumpAndSettle();
      expect(stream(followingID), findsNothing);

      logic.scrollController.jumpTo(180);
      await tester.pumpAndSettle();
      expect(logic.newMessages.awayFromLatest.value, isTrue);
      final visible = find
          .byWidgetPredicate((widget) =>
              widget is ChatMessageContentAnchor &&
              !widget.messageID.startsWith('assistant-stream:'))
          .evaluate()
          .where((element) {
        final rect = tester.getRect(find.byWidget(element.widget));
        return rect.top >= viewport.top && rect.bottom <= viewport.bottom;
      }).toList();
      expect(visible, isNotEmpty);
      final anchorID =
          (visible.first.widget as ChatMessageContentAnchor).messageID;
      final top = tester.getRect(source(anchorID)).top;
      fixture.im.recvNewMessage(aiOpenimStreamFragment('reading-0',
          streamID: readingID, index: 0, text: '下一轮预览。\n\n'));
      await tester.pumpAndSettle();
      expect(tester.getRect(source(anchorID)).top, closeTo(top, 1));
      fixture.im.recvNewMessage(aiOpenimStreamFragment('reading-1',
          streamID: readingID, index: 1, text: growth));
      await tester.pumpAndSettle();
      expect(tester.getRect(source(anchorID)).top, closeTo(top, 1));
      expect(logic.newMessages.unseenCount.value, 0);
      fixture.im.recvNewMessage(
          aiOpenimStreamFinal('reading-final-$dark', '下一轮的完整正文', readingID));
      await tester.pumpAndSettle();
      expect(tester.getRect(source(anchorID)).top, closeTo(top, 1));
      expect(logic.newMessages.awayFromLatest.value, isTrue);
      expect(logic.newMessages.unseenCount.value, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      logic.onDelete();
      fixture.histories.clear();
    }
  });

  streamTest('dated history hides stream rows and buffers only the final reply',
      (tester) async {
    final latest = List.generate(
        30,
        (index) =>
            aiOpenimText('latest-$index', '最新正文 $index', time: 1000 + index));
    final logic = await mount(tester, history: latest);
    final target = aiOpenimText('dated-target', '较早日期的正文', time: 100);
    final jump = logic.jumpToDateMessage(target);
    await tester.pump();
    fixture.histories.last.complete([
      ...List.generate(
          20,
          (index) => aiOpenimText('dated-before-$index', '此前正文 $index',
              time: 80 + index)),
      target,
    ], isEnd: false);
    fixture.newerHistories.single.complete([
      target,
      ...List.generate(
          20,
          (index) => aiOpenimText('dated-after-$index', '此后正文 $index',
              time: 101 + index)),
    ], isEnd: false);
    await tester.pumpAndSettle();
    expect(await jump, isTrue);
    expect(logic.viewingHistory.value, isTrue);
    final historicalIDs =
        logic.messageList.map((message) => message.clientMsgID).toList();
    fixture.im.recvNewMessage(aiOpenimStreamFragment('dated-chunk',
        streamID: 'while-dated', index: 0, text: '不应混入旧日期切片的流'));
    await tester.pump();
    expect(logic.assistantStreams.snapshots.single.streamID, 'while-dated');
    expect(stream('while-dated'), findsNothing);
    expect(
        logic.messageList.map((message) => message.clientMsgID), historicalIDs);
    fixture.im.recvNewMessage(aiOpenimStreamFinal(
        'dated-buffered-final', '回到最新才能看到的完整回复', 'while-dated'));
    await tester.pump();
    expect(
        logic.messageList.map((message) => message.clientMsgID), historicalIDs);
    expect(logic.scrollingCacheMessageList.single.clientMsgID,
        'dated-buffered-final');
    expect(logic.newMessages.unseenCount.value, 1);
    logic.scrollBottom();
    await tester.pump();
    fixture.histories.last.complete(latest);
    await tester.pumpAndSettle();
    expect(logic.viewingHistory.value, isFalse);
    expect(logic.scrollingCacheMessageList, isEmpty);
    expect(
        logic.messageList
            .where((message) => message.clientMsgID == 'dated-buffered-final'),
        hasLength(1));
    expect(stream('while-dated'), findsNothing);
    expect(logic.newMessages.unseenCount.value, 0);
    expect(tester.takeException(), isNull);
  });

  streamTest(
      'reconnect finalizes partials and rejects packets from another IM account',
      (tester) async {
    final logic = await mount(tester);
    final wrongRecipient = aiOpenimStreamFragment('wrong-recipient',
        streamID: 'wrong-recipient', index: 0, text: '其他用户的内容')
      ..recvID = 'another-account';
    final wrongSender = aiOpenimStreamFragment('wrong-sender',
        streamID: 'wrong-sender', index: 0, text: '非助理发出的内容')
      ..sendID = 'another-peer';
    fixture.im.recvNewMessage(wrongRecipient);
    fixture.im.recvNewMessage(wrongSender);
    await tester.pump();
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(logic.messageList, isEmpty);
    fixture.im.recvNewMessage(aiOpenimStreamFragment('before-reconnect',
        streamID: 'reconnected', index: 0, text: '网络断开前已经显示的片段'));
    await tester.pump();
    expect(stream('reconnected'), findsOneWidget);
    fixture.im.imSdkStatus(IMSdkStatus.syncEnded);
    await tester.pump();
    expect(fixture.histories, hasLength(2));
    fixture.histories.last.complete([
      aiOpenimStreamFinal('reconnect-final', '同步历史取得的完整回复', 'reconnected'),
    ]);
    await tester.pumpAndSettle();
    expect(stream('reconnected'), findsNothing);
    expect(logic.assistantStreams.snapshots, isEmpty);
    expect(logic.messageList.single.clientMsgID, 'reconnect-final');
    fixture.im.recvNewMessage(aiOpenimStreamFragment('accepted',
        streamID: 'current', index: 0, text: '当前账号的预览'));
    await tester.pump();
    final ownedCallback = fixture.im.onRecvNewMessage!;
    OpenIM.iMManager.userID = 'another-account';
    ownedCallback(aiOpenimStreamFragment('after-account-change',
        streamID: 'current', index: 1, text: '切换账号后不能接上'));
    ownedCallback(aiOpenimStreamFragment('new-other-stream',
        streamID: 'other', index: 0, text: '切换账号后的新流'));
    await tester.pump();
    expect(logic.assistantStreams.snapshots.single.text, '当前账号的预览');
    expect(logic.messageList.single.clientMsgID, 'reconnect-final');
    expect(fixture.app.notifications, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
