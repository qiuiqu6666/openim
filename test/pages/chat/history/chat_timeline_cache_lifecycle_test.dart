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
}) =>
    ChatTimelineController(
      accountID: 'me',
      currentAccountID: () => 'me',
      isSessionCurrent: sessionCurrent,
      conversation: () =>
          ConversationInfo(conversationID: 'chat', latestMsg: latest),
      fetch: ({required count, startMsg}) async =>
          AdvancedMessage(messageList: [], isEnd: true),
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
