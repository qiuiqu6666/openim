import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/pages/official_account/presentation/official_account_timeline_policy.dart';
import 'package:openim/services/chat_history_cache.dart';

ChatTimelineController _timeline({void Function(List<Message>)? marker}) =>
    ChatTimelineController(
      accountID: 'self',
      currentAccountID: () => 'self',
      conversation: () => ConversationInfo(conversationID: 'single'),
      fetch: ({required count, startMsg}) async =>
          AdvancedMessage(messageList: [], isEnd: true),
      isClosed: () => false,
      onFirstPage: () {},
      captureOffset: () => 0,
      restoreOffset: (_) {},
      onFirstLoaded: () {},
      timelineTimeMarker: marker,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(ChatHistoryCache.clear);
  tearDown(ChatHistoryCache.clear);
  final midday = DateTime(2026, 10, 5, 12).millisecondsSinceEpoch;

  test('ordinary timeline keeps six-minute last-displayed-date behavior', () {
    final timeline = _timeline();
    timeline.initialize(prefetch: false);
    timeline.messageList.value = [
      Message(clientMsgID: 'first', sendTime: midday),
      Message(clientMsgID: 'second', sendTime: midday + 310000),
      Message(clientMsgID: 'third', sendTime: midday + 360000),
    ];
    timeline.indexOfMessage(0);
    expect(
        timeline.messageList
            .map((message) => message.exMap['showTime'] == true),
        [true, false, true]);
    timeline.close();
  });

  test('optional official callback recalculates on history window changes', () {
    final timeline = _timeline(marker: OfficialAccountTimelinePolicy.markTimes);
    timeline.initialize(prefetch: false);
    final second = Message(
        clientMsgID: 'second',
        contentType: MessageType.text,
        sendTime: midday + 301000);
    timeline.messageList.value = [
      Message(
          clientMsgID: 'first',
          contentType: MessageType.text,
          sendTime: midday),
      second,
    ];
    timeline.indexOfMessage(0);
    expect(second.exMap['showTime'], isTrue);
    timeline.messageList.insert(
        1,
        Message(
            clientMsgID: 'middle',
            contentType: MessageType.text,
            sendTime: midday + 1000));
    timeline.indexOfMessage(0);
    expect(second.exMap['showTime'], isNull);
    timeline.close();
  });

  test('receipt refreshes reuse timestamp metadata and changed times repair it',
      () {
    final timeline = _timeline();
    timeline.initialize(prefetch: false);
    final first = Message(clientMsgID: 'first', sendTime: midday)
      ..exMap = const {'unrelated': 'keep'};
    final second = Message(clientMsgID: 'second', sendTime: midday + 360000)
      ..exMap = const {'unrelated': 'keep'};
    timeline.messageList.value = [first, second];
    timeline.indexOfMessage(0);
    final firstMetadata = first.exMap;
    final secondMetadata = second.exMap;
    first.isRead = true;
    timeline.messageList.refresh();
    timeline.indexOfMessage(0);
    expect(identical(first.exMap, firstMetadata), isTrue);
    expect(identical(second.exMap, secondMetadata), isTrue);

    second.sendTime = midday + 1000;
    timeline.messageList.refresh();
    timeline.indexOfMessage(0);
    expect(identical(first.exMap, firstMetadata), isTrue);
    expect(second.exMap['showTime'], isNull);
    expect(second.exMap['unrelated'], 'keep');
    expect(secondMetadata['showTime'], isTrue,
        reason: 'A changed divider must not mutate shared metadata snapshots');
    timeline.close();
  });
}
