import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';

Message _message(String id) => Message(
      clientMsgID: id,
      sendTime: 1,
      contentType: MessageType.text,
      status: MessageStatus.succeeded,
    );

ChatTimelineController _timeline({
  required bool Function() sessionCurrent,
  Message? latest,
  Future<List<Message>> Function()? snapshot,
  List<Message> rows = const [],
}) =>
    ChatTimelineController(
      accountID: 'me',
      currentAccountID: () => 'me',
      isSessionCurrent: sessionCurrent,
      conversation: () =>
          ConversationInfo(conversationID: 'chat', latestMsg: latest),
      fetchLocalSnapshot: snapshot,
      fetch: ({required count, startMsg}) async =>
          AdvancedMessage(messageList: rows, isEnd: true),
      isClosed: () => false,
      onFirstPage: () {},
      captureOffset: () => 0,
      restoreOffset: (_) {},
      onFirstLoaded: () {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  for (final change in ['none', 'delivery', 'clear', 'credentials', 'latest']) {
    test('production reentry restores only a current preview snapshot: $change',
        () async {
      final originalToken = OpenIM.iMManager.token;
      addTearDown(() => OpenIM.iMManager.token = originalToken);
      final first =
          _timeline(sessionCurrent: () => true, rows: [_message('loaded')]);
      first.initialize(prefetch: false);
      await first.loadOlder();
      first.close();
      if (change == 'delivery') ChatHistoryCache.receivedMessage();
      if (change == 'clear') ChatHistoryCache.removeConversation('me', 'chat');
      if (change == 'credentials') OpenIM.iMManager.token = 'replacement-token';
      final pending = Completer<List<Message>>();
      final reopened = _timeline(
          sessionCurrent: () => true,
          snapshot: () => pending.future,
          latest: change == 'latest' ? _message('newer') : null);
      reopened.initialize(prefetch: false);
      final canRestore = !['clear', 'credentials', 'latest'].contains(change);
      expect(reopened.initialWindowReady.value, canRestore);
      expect(reopened.messageList.map((m) => m.clientMsgID),
          canRestore ? ['loaded'] : isEmpty);
      expect(reopened.hasLoadedHistory, isFalse);
      reopened.close();
      pending.complete([]);
      await Future<void>.delayed(Duration.zero);
    });
  }

  testWidgets('later reentry and rapid reopen retain rows until SDK refresh',
      (tester) async {
    ChatHistoryCache.write('me', 'chat', [_message('existing')],
        readySession: ('me', OpenIM.iMManager.token));
    await tester.pump(const Duration(minutes: 5));
    final pending = Completer<List<Message>>();
    final first =
        _timeline(sessionCurrent: () => true, snapshot: () => pending.future);
    first.initialize(prefetch: false);
    expect(first.messageList.single.clientMsgID, 'existing');
    first.close();
    final second = _timeline(
        sessionCurrent: () => true,
        snapshot: () => pending.future,
        rows: [_message('existing'), _message('fresh')]);
    second.initialize(prefetch: false);
    expect(second.initialWindowReady.value, isTrue);
    expect(second.messageList.single.clientMsgID, 'existing');
    final refresh = second.loadOlder();
    await tester.pump();
    await refresh;
    expect(second.messageList.map((m) => m.clientMsgID), ['existing', 'fresh']);
    second.close();
    pending.complete([]);
    await tester.pump();
  });

  test('ordinary route closure preserves its current session snapshot', () {
    final timeline = _timeline(sessionCurrent: () => true);
    timeline.initialize(prefetch: false);
    timeline.messageList.add(_message('kept'));
    timeline.close();
    expect(ChatHistoryCache.read('me', 'chat').single.clientMsgID, 'kept');
  });

  test('same-account credential change prevents the final snapshot write', () {
    var current = true;
    final timeline = _timeline(sessionCurrent: () => current);
    timeline.initialize(prefetch: false);
    timeline.messageList.add(_message('old-session'));
    current = false;
    timeline.close();
    expect(ChatHistoryCache.read('me', 'chat'), isEmpty);
  });

  test('bulk deletion prevents an evicted latest-message seed from returning',
      () {
    for (var i = 0; i < 1025; i++) {
      ChatHistoryCache.removeMessage('me', 'deleted-$i');
    }
    final timeline =
        _timeline(sessionCurrent: () => true, latest: _message('deleted-0'));
    timeline.initialize(prefetch: false);
    expect(timeline.messageList, isEmpty);
    timeline.close();
    ChatHistoryCache.clear();
    expect(ChatHistoryCache.canSeedLatest, isTrue);
  });
}
