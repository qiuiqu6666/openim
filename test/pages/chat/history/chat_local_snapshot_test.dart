import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';

Message row(String id, int time) => Message(
    clientMsgID: id,
    sendTime: time,
    seq: time,
    status: MessageStatus.succeeded,
    contentType: MessageType.text);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  for (final outcome in [
    'display',
    'private-existing',
    'remote-first',
    'clear',
    'session',
    'private'
  ]) {
    test('restart displays local rows without waiting for sync: $outcome',
        () async {
      final local = Completer<List<Message>>();
      final remote = Completer<AdvancedMessage>();
      final proof = Completer<AdvancedMessage>();
      var session = true;
      final info = ConversationInfo(
          conversationID: 'chat',
          isPrivateChat: outcome == 'private-existing',
          latestMsg: row('stored', 1));
      final timeline = ChatTimelineController(
          accountID: 'me',
          currentAccountID: () => 'me',
          isSessionCurrent: () => session,
          conversation: () => info,
          fetchDisplaySnapshot: () => local.future,
          fetchWindow: () => proof.future,
          canPaintInitialWindow: () => false,
          fetch: ({required count, startMsg}) => remote.future,
          isClosed: () => false,
          onFirstPage: () {},
          captureOffset: () => 0,
          restoreOffset: (_) {},
          onFirstLoaded: () {});
      addTearDown(timeline.close);
      timeline.initialize();
      if (outcome == 'remote-first') {
        remote.complete(
            AdvancedMessage(messageList: [row('fresh', 100)], isEnd: true));
        await Future<void>.delayed(Duration.zero);
      }
      if (outcome == 'clear') timeline.clear();
      if (outcome == 'session') session = false;
      if (outcome == 'private') info.isPrivateChat = true;
      local.complete([
        row('stored', 1),
        Message.fromJson({
          'clientMsgID': 'private-row',
          'attachedInfoElem': {'isPrivateChat': true}
        }),
      ]);
      await Future<void>.delayed(Duration.zero);
      if (outcome == 'display' || outcome == 'private-existing') {
        expect(timeline.messageList.single.clientMsgID, 'stored');
        expect(timeline.initialWindowReady.value, isTrue);
        expect(timeline.hasLoadedHistory, isFalse);
        expect(timeline.hasPublishableWindow, isFalse);
      } else {
        expect(timeline.messageList.any((m) => m.clientMsgID == 'stored'),
            isFalse);
      }
      if (!remote.isCompleted) {
        remote.complete(AdvancedMessage(
            messageList: [row('stored', 1), row('fresh', 100)], isEnd: true));
      }
      await Future<void>.delayed(Duration.zero);
      if (outcome == 'display' || outcome == 'private-existing') {
        expect(timeline.messageList.map((m) => m.clientMsgID),
            ['stored', 'fresh']);
        expect(timeline.hasLoadedHistory, isTrue);
      }
      timeline.close();
      proof.complete(AdvancedMessage(messageList: []));
      await Future<void>.delayed(Duration.zero);
    });
  }

  for (final outcome in [
    'normal',
    'empty-remote',
    'remote-first',
    'clear',
    'close',
    'session',
    'private',
    'delete'
  ]) {
    test('cold local snapshot while network is stalled: $outcome', () async {
      final local = Completer<List<Message>>();
      final remote = Completer<AdvancedMessage>();
      var session = true;
      var loaded = 0;
      final conversation = ConversationInfo(conversationID: 'chat');
      final timeline = ChatTimelineController(
          accountID: 'me',
          currentAccountID: () => 'me',
          isSessionCurrent: () => session,
          conversation: () => conversation,
          fetchLocalSnapshot: () => local.future,
          fetch: ({required count, startMsg}) => remote.future,
          isClosed: () => false,
          onFirstPage: () {},
          captureOffset: () => 0,
          restoreOffset: (_) {},
          onFirstLoaded: () => loaded++);
      addTearDown(timeline.close);
      timeline.initialize();
      if (outcome == 'remote-first') {
        remote.complete(
            AdvancedMessage(messageList: [row('fresh', 100)], isEnd: true));
        await Future<void>.delayed(Duration.zero);
      }
      if (outcome == 'clear') timeline.clear();
      if (outcome == 'close') timeline.close();
      if (outcome == 'session') session = false;
      if (outcome == 'private') conversation.isPrivateChat = true;
      if (outcome == 'delete') ChatHistoryCache.removeMessage('me', 'local');
      local.complete([row('local', 1)]);
      await Future<void>.delayed(Duration.zero);
      if (outcome == 'normal' || outcome == 'empty-remote') {
        expect(timeline.messageList.single.clientMsgID, 'local');
        expect(timeline.hasLoadedHistory, isFalse);
        expect(timeline.initialHistoryLoading.value, isTrue);
        expect(loaded, 0);
        if (outcome == 'normal') {
          timeline.appendIncoming(row('live', 101), trim: false);
        }
      } else {
        expect(
            timeline.messageList.any((m) => m.clientMsgID == 'local'), isFalse);
      }
      if (!remote.isCompleted) {
        remote.complete(AdvancedMessage(
            messageList: outcome == 'empty-remote' ? [] : [row('fresh', 100)],
            isEnd: true));
      }
      await Future<void>.delayed(Duration.zero);
      if (outcome == 'empty-remote') {
        expect(timeline.messageList.single.clientMsgID, 'local');
        expect(timeline.hasLoadedHistory, isFalse);
        expect(timeline.historyError.value, isNotNull);
        expect(loaded, 0);
      }
      if (outcome == 'normal') {
        expect(
            timeline.messageList.map((m) => m.clientMsgID), ['fresh', 'live']);
        expect(timeline.hasLoadedHistory, isTrue);
        expect(loaded, 1);
      }
    });
  }
}
