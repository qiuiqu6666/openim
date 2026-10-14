import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/services/chat_history_cache.dart';

Message row(int n) => Message(
    clientMsgID: 'm$n',
    seq: n,
    sendTime: n,
    contentType: MessageType.text,
    status: MessageStatus.succeeded);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);

  test(
      'deferred disjoint latest keeps both paging anchors until explicit return',
      () async {
    final first = Completer<AdvancedMessage>();
    final cursors = <String?>[];
    var firstRead = true;
    final timeline = ChatTimelineController(
        accountID: 'me',
        currentAccountID: () => 'me',
        conversation: () => ConversationInfo(conversationID: 'chat'),
        fetchLocalSnapshot: () async => [row(10), row(11)],
        fetch: ({required count, startMsg}) async {
          cursors.add(startMsg?.clientMsgID);
          if (firstRead) {
            firstRead = false;
            return first.future;
          }
          return AdvancedMessage(
              messageList: startMsg == null ? [row(100), row(101)] : [row(9)],
              isEnd: false);
        },
        fetchNewer: ({required count, startMsg}) async =>
            AdvancedMessage(messageList: [row(12)], isEnd: false),
        isClosed: () => false,
        onFirstPage: () {},
        captureOffset: () => 0,
        restoreOffset: (_) {},
        onFirstLoaded: () {});
    addTearDown(timeline.close);
    timeline.initialize();
    await Future<void>.delayed(Duration.zero);
    timeline.recordPaintedRows(['m10']);
    first.complete(
        AdvancedMessage(messageList: [row(100), row(101)], isEnd: false));
    await Future<void>.delayed(Duration.zero);
    expect(timeline.messageList.map((m) => m.seq), [10, 11]);
    expect(timeline.latestDeferred.value, isTrue);
    await timeline.loadOlder();
    expect(cursors, [null, 'm10']);
    expect(timeline.messageList.map((m) => m.seq), [9, 10, 11]);
    expect(timeline.latestDeferred.value, isTrue);
    await timeline.refresh();
    expect(cursors, [null, 'm10'],
        reason: 'sync must not repeatedly replace or poll a held window');
    await timeline.returnToLatest();
    expect(timeline.messageList.map((m) => m.seq), [100, 101]);
    expect(timeline.latestDeferred.value, isFalse);
    await timeline.loadOlder();
    expect(cursors.last, 'm100',
        reason:
            'missing history remains reachable from the installed latest page');
  });
}
