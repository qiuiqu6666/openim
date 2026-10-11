import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/conversation/updates/conversation_latest_sync.dart';
import 'package:openim_common/openim_common.dart';

Message _message(String id, {int type = ConversationType.single}) => Message(
    clientMsgID: id,
    contentType: MessageType.text,
    sessionType: type,
    sendID: 'peer',
    recvID: 'self',
    groupID: type == ConversationType.superGroup ? 'group' : null);

void main() {
  late ConversationLatestSync sync;
  late List<List<String>> reads;
  late List<List<ConversationInfo>> published;
  late List<Completer<List<ConversationInfo>>> replies;

  setUp(() {
    OpenIM.iMManager.userID = 'self';
    reads = [];
    replies = [];
    published = [];
    sync = ConversationLatestSync(
      isActive: () => OpenIM.iMManager.userID == 'self',
      publish: published.add,
      flushChanges: () {},
      resolveID: (request) async => request.conversationID ?? request.sourceID!,
      read: (ids) {
        reads.add(ids);
        final reply = Completer<List<ConversationInfo>>();
        replies.add(reply);
        return reply.future;
      },
    );
  });
  tearDown(() {
    sync.close();
    for (final reply in replies) {
      if (!reply.isCompleted) reply.complete([]);
    }
  });

  testWidgets('1200 authoritative callbacks avoid all repair reads',
      (tester) async {
    for (var i = 0; i < 1200; i++) {
      final message = _message('$i');
      final row = ConversationInfo(
          conversationID: 'peer',
          userID: 'peer',
          conversationType: ConversationType.single,
          latestMsg: message);
      // Exercise both SDK event orders.
      if (i.isEven) sync.observeMessage(message);
      sync.conversationsUpdated([row]);
      if (i.isOdd) sync.observeMessage(message);
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, isEmpty);
  });
  testWidgets('older callback cannot cancel latest repair or explicit refresh',
      (tester) async {
    sync.observeMessage(_message('new'));
    sync.conversationsUpdated([
      ConversationInfo(
          conversationID: 'peer',
          userID: 'peer',
          conversationType: ConversationType.single,
          latestMsg: _message('old'))
    ]);
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, hasLength(1));
    replies.single.complete([]);
    await tester.pump();
    sync.requestRefresh(
        ConversationRefreshRequest(accountID: 'self', conversationID: 'peer'));
    sync.conversationsUpdated([
      ConversationInfo(
          conversationID: 'peer',
          userID: 'peer',
          conversationType: ConversationType.single,
          latestMsg: _message('new'))
    ]);
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, hasLength(2));
    replies.last.complete([]);
    await tester.pump();
  });

  testWidgets('message bursts batch single and group snapshot reads',
      (tester) async {
    for (var i = 0; i < 1000; i++) {
      sync.observeMessage(_message('$i'));
    }
    sync.observeMessage(_message('group', type: ConversationType.superGroup));
    expect(reads, isEmpty);
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, [
      ['peer', 'group']
    ]);
    replies.single.complete([
      ConversationInfo(conversationID: 'peer', latestMsg: _message('1000')),
      ConversationInfo(conversationID: 'group', unreadCount: 3),
    ]);
    await tester.pump();
    expect(
        published.single.map((row) => row.conversationID), ['peer', 'group']);
    expect(published.single.last.unreadCount, 3);
  });

  testWidgets('online deltas, typing and another account do not refresh',
      (tester) async {
    sync.observeMessage(_message('typing')..contentType = MessageType.typing);
    sync.observeMessage(_message('delta')
      ..customElem = CustomElem(description: 'assistantStream'));
    sync.observeMessage(_message('other')..recvID = 'other-account');
    sync.requestRefresh(ConversationRefreshRequest(
        accountID: 'other-account', conversationID: 'peer'));
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, isEmpty);
  });

  testWidgets(
      'callback during query wins, including deletion of latest message',
      (tester) async {
    sync.observeMessage(_message('old'));
    await tester.pump(ConversationLatestSync.settleDelay);
    sync.conversationsChanged(['peer']);
    replies.single.complete([
      ConversationInfo(conversationID: 'peer', latestMsg: _message('old')),
      ConversationInfo(conversationID: 'unrequested'),
    ]);
    await tester.pump();
    expect(published.single, isEmpty);
  });

  testWidgets('new signal during query schedules one later snapshot',
      (tester) async {
    sync.observeMessage(_message('first'));
    await tester.pump(ConversationLatestSync.settleDelay);
    for (var i = 0; i < 20; i++) {
      sync.observeMessage(_message('later-$i'));
    }
    await tester.pump(const Duration(seconds: 1));
    expect(reads, hasLength(1));
    replies.first.complete([]);
    await tester.pump();
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, hasLength(2));
    replies.last.complete([]);
    await tester.pump(const Duration(seconds: 5));
    expect(reads, hasLength(2));
  });

  for (final invalidate in ['close', 'reset', 'account', 'delete']) {
    testWidgets('$invalidate prevents old query from restoring a row',
        (tester) async {
      sync.observeMessage(_message('old'));
      await tester.pump(ConversationLatestSync.settleDelay);
      switch (invalidate) {
        case 'close':
          sync.close();
        case 'reset':
          sync.reset();
        case 'account':
          OpenIM.iMManager.userID = 'another';
        case 'delete':
          sync.discard(ConversationInfo(
              conversationID: 'peer',
              userID: 'peer',
              conversationType: ConversationType.single));
      }
      replies.single.complete([ConversationInfo(conversationID: 'peer')]);
      await tester.pump();
      expect(published.expand((batch) => batch), isEmpty);
    });
  }

  testWidgets('delete cancels pending message and chat-leave refreshes',
      (tester) async {
    sync.observeMessage(_message('old'));
    sync.requestRefresh(
        ConversationRefreshRequest(accountID: 'self', conversationID: 'peer'));
    sync.discard(ConversationInfo(
        conversationID: 'peer',
        userID: 'peer',
        conversationType: ConversationType.single));
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, isEmpty);
  });

  testWidgets('read failure is silent and does not poll; next signal can retry',
      (tester) async {
    sync.observeMessage(_message('first'));
    await tester.pump(ConversationLatestSync.settleDelay);
    replies.single.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(reads, hasLength(1));
    expect(published, isEmpty);
    sync.observeMessage(_message('retry'));
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, hasLength(2));
    replies.last.complete([]);
    await tester.pump();
  });

  testWidgets('hung read times out and a later signal is still served',
      (tester) async {
    sync.observeMessage(_message('first'));
    await tester.pump(ConversationLatestSync.settleDelay);
    await tester.pump(const Duration(seconds: 5));
    sync.observeMessage(_message('next'));
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads, hasLength(2));
    replies.last.complete([ConversationInfo(conversationID: 'peer')]);
    replies.first.complete([ConversationInfo(conversationID: 'old')]);
    await tester.pump();
    expect(published.single.single.conversationID, 'peer');
  });

  testWidgets('large bursts use bounded batches without dropping targets',
      (tester) async {
    for (var i = 0; i < 100; i++) {
      sync.requestRefresh(ConversationRefreshRequest(
          accountID: 'self', conversationID: 'chat-$i'));
    }
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads.single, hasLength(64));
    replies.first.complete([]);
    await tester.pump();
    await tester.pump(ConversationLatestSync.settleDelay);
    expect(reads.last, hasLength(36));
    replies.last.complete([]);
    await tester.pump();
    expect(reads.expand((batch) => batch).toSet(), hasLength(100));
  });
}
