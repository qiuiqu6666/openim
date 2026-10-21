import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';

import 'message_window_ingress_test.dart' show window;

Message row(int seq) => Message(
    clientMsgID: 'm$seq',
    seq: seq,
    sendTime: seq,
    contentType: MessageType.text,
    status: MessageStatus.succeeded);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  for (final source in ['cache', 'display', 'native', 'late-preview']) {
    test('entry rejects older $source rows until latest is available',
        () async {
      final info = ConversationInfo(
          conversationID: 'chat',
          latestMsg: row(source == 'late-preview' ? 1 : 2));
      final display = Completer<List<Message>>();
      final local = Completer<AdvancedMessage>();
      final remote = Completer<AdvancedMessage>();
      if (source == 'cache') {
        ChatHistoryCache.write('me', 'chat', [row(1)],
            readySession: ('me', OpenIM.iMManager.token));
      }
      final timeline = ChatTimelineController(
          accountID: 'me',
          currentAccountID: () => 'me',
          conversation: () => info,
          fetchDisplaySnapshot: () => display.future,
          fetchWindow: () => local.future,
          fetch: ({required count, startMsg}) => remote.future,
          isClosed: () => false,
          onFirstPage: () {},
          captureOffset: () => 0,
          restoreOffset: (_) {},
          onFirstLoaded: () {});
      addTearDown(timeline.close);
      timeline.initialize();
      if (source == 'late-preview') info.latestMsg = row(2);
      display.complete([row(1)]);
      local.complete(AdvancedMessage(messageList: [row(1)], window: window(1)));
      await Future<void>.delayed(Duration.zero);
      expect(timeline.initialWindowReady.value, isFalse);
      expect(timeline.messageList, isEmpty);
      remote.complete(AdvancedMessage(
          messageList: [row(1), row(2)], window: window(2), isEnd: true));
      await Future<void>.delayed(Duration.zero);
      expect(timeline.initialWindowReady.value, isTrue);
      expect(timeline.messageList.map((m) => m.clientMsgID), ['m1', 'm2']);
      expect(timeline.hasLoadedHistory, isTrue);
    });
  }

  for (final kind in ['current', 'typing', 'removed', 'sending', 'failed']) {
    test('safe $kind preview retains immediate local display', () async {
      final latest = row(kind == 'current' ? 1 : 2);
      if (kind == 'typing') latest.contentType = MessageType.typing;
      if (kind == 'sending') latest.status = MessageStatus.sending;
      if (kind == 'failed') latest.status = MessageStatus.failed;
      if (kind == 'removed') ChatHistoryCache.removeMessage('me', 'm2');
      final timeline = ChatTimelineController(
          accountID: 'me',
          currentAccountID: () => 'me',
          conversation: () =>
              ConversationInfo(conversationID: 'chat', latestMsg: latest),
          fetchDisplaySnapshot: () async => [row(1)],
          fetch: ({required count, startMsg}) async =>
              AdvancedMessage(messageList: []),
          isClosed: () => false,
          onFirstPage: () {},
          captureOffset: () => 0,
          restoreOffset: (_) {},
          onFirstLoaded: () {});
      addTearDown(timeline.close);
      timeline.initialize(prefetch: false);
      await Future<void>.delayed(Duration.zero);
      expect(timeline.initialWindowReady.value, isTrue);
      expect(timeline.messageList.single.clientMsgID, 'm1');
    });
  }

  test('stale prepared native page remains retryable without painting old tail',
      () async {
    var through = 1;
    final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () =>
            ConversationInfo(conversationID: 'chat', latestMsg: row(2)),
        fetchLocalSnapshot: () async => [],
        fetch: ({required count, startMsg}) async => AdvancedMessage(
            messageList: [for (var i = 1; i <= through; i++) row(i)],
            window: window(through),
            isEnd: true),
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {});
    addTearDown(timeline.close);
    timeline.initialize(prefetch: false);
    await timeline.loadOlder();
    expect(timeline.initialWindowReady.value, isFalse);
    expect(timeline.messageList, isEmpty);
    expect(timeline.historyError.value, isNotNull);
    through = 2;
    await timeline.loadOlder();
    expect(timeline.initialWindowReady.value, isTrue);
    expect(timeline.historyError.value, isNull);
    expect(timeline.messageList.map((m) => m.clientMsgID), ['m1', 'm2']);
  });
}
