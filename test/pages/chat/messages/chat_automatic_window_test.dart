import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_timeline_controller.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/services/chat_history_cache.dart';

Message _message(int id, {int status = MessageStatus.succeeded}) => Message(
      clientMsgID: 'row-$id',
      sendID: 'self',
      contentType: MessageType.text,
      sendTime: id,
      seq: id,
      status: status,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ChatTimelineController timeline;
  late ChatDeliveryController delivery;
  late Future<Message> Function(Message) transport;

  setUp(() {
    OpenIM.iMManager.userID = 'self';
    ChatHistoryCache.clear();
    final conversation = ConversationInfo(
        conversationID: 'chat', userID: 'peer', unreadCount: 0);
    timeline = ChatTimelineController(
      accountID: 'self',
      currentAccountID: () => 'self',
      conversation: () => conversation,
      fetch: ({required count, startMsg}) async =>
          AdvancedMessage(messageList: [], isEnd: false),
      fetchNewer: ({required count, startMsg}) async =>
          AdvancedMessage(messageList: [], isEnd: false),
      isClosed: () => false,
      onFirstPage: () {},
      captureOffset: () => 0,
      restoreOffset: (_) {},
      onFirstLoaded: () {},
    )..initialize(prefetch: false);
    transport = (message) async => message;
    delivery = ChatDeliveryController(
      accountID: 'self',
      currentAccountID: () => 'self',
      messageList: timeline.messageList,
      conversation: () => conversation,
      isClosed: () => false,
      groupStatus: () => null,
      scrollBottom: () {},
      resetInput: (_) {},
      onTimelineChanged: timeline.trimLatestWindow,
      sendRaw: (message, _) => transport(message),
    );
  });
  tearDown(() {
    delivery.close();
    timeline.close();
    ChatHistoryCache.clear();
  });

  test(
      '1200 incoming appends publish once each and preserve exact latest window',
      () async {
    timeline.messageList.value = List.generate(600, _message);
    var changes = 0;
    final subscription = timeline.messageList.listen((_) => changes++);
    for (var id = 600; id < 1800; id++) {
      timeline.appendIncoming(_message(id), trim: true);
      expect(timeline.containsMessage('row-$id'), isTrue);
    }
    expect(changes, 1200);
    expect(timeline.messageList, hasLength(600));
    expect(timeline.messageList.first.clientMsgID, 'row-1200');
    expect(timeline.containsMessage('row-600'), isFalse);
    await subscription.cancel();
  });

  test('outgoing messages stay bounded without any incoming SDK callback',
      () async {
    timeline.messageList.value = List.generate(600, _message);
    for (var id = 600; id < 800; id++) {
      await delivery.send(_message(id));
    }
    expect(timeline.messageList, hasLength(600));
    expect(timeline.messageList.first.clientMsgID, 'row-200');
    expect(timeline.messageList.last.clientMsgID, 'row-799');
    expect(timeline.historyHasMore.value, isTrue);
  });

  test('pending and failed rows do not evict the successful latest window',
      () async {
    timeline.messageList.value =
        List.generate(700, (id) => _message(id, status: MessageStatus.sending));
    timeline.messageList.first.status = MessageStatus.failed;
    await delivery.send(_message(700));
    expect(timeline.messageList, hasLength(701));
    expect(timeline.messageList.last.clientMsgID, 'row-700');
    expect(timeline.messageList.first.status, MessageStatus.failed);
  });

  test('a staged send finishing outside the newest window can be released',
      () async {
    final staged = _message(0, status: MessageStatus.sending);
    timeline.messageList.value = [
      staged,
      ...List.generate(700, (id) => _message(id + 1)),
    ];
    timeline.trimLatestWindow();
    expect(timeline.messageList, hasLength(601));
    final completion = Completer<Message>();
    transport = (_) => completion.future;
    final sending = delivery.send(staged, addToUI: false);
    completion.complete(_message(0));
    await sending;
    expect(timeline.messageList, hasLength(600));
    expect(timeline.messageList.last.clientMsgID, 'row-700');
    expect(timeline.messageList.any((m) => m.clientMsgID == 'row-0'), isFalse);
  });

  test('history windows keep their rows when a send completes', () async {
    await timeline.jumpTo(_message(1000));
    expect(timeline.viewingHistory.value, isTrue);
    timeline.messageList.value = List.generate(1000, _message);
    await delivery.send(_message(1000));
    expect(timeline.messageList, hasLength(1001));
    expect(timeline.messageList.first.clientMsgID, 'row-0');
  });
}
