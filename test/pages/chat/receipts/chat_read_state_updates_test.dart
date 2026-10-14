import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/receipts/chat_read_receipts.dart';

Message _message(String id, {bool private = false}) => Message(
      clientMsgID: id,
      seq: 1,
      sendID: 'peer',
      contentType: MessageType.text,
      isRead: false,
      attachedInfoElem: private ? AttachedInfoElem(isPrivateChat: true) : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late RxList<Message> messages;
  late ChatReadReceipts receipts;
  late List<Set<String>> changed;
  late StreamSubscription<List<Message>> subscription;
  late int timelineRefreshes;

  setUp(() {
    OpenIM.iMManager.userID = 'self';
    messages = <Message>[].obs;
    changed = [];
    timelineRefreshes = 0;
    receipts = ChatReadReceipts(
      messageList: messages,
      conversation: () => ConversationInfo(conversationID: 'chat'),
      isClosed: () => OpenIM.iMManager.userID != 'self',
      onReadStateChanged: changed.add,
    );
    subscription = messages.listen((_) => timelineRefreshes++);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() async {
    receipts.close();
    await subscription.cancel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('receipt burst only publishes changed row IDs', (tester) async {
    messages
        .addAll([_message('read-a'), _message('read-b'), _message('unread')]);
    await tester.pump(Duration.zero);
    timelineRefreshes = 0;
    for (var i = 0; i < 50; i++) {
      receipts.applyC2CReceipt([
        ReadReceiptInfo(userID: 'peer', msgIDList: ['read-a', 'read-b']),
        ReadReceiptInfo(userID: 'other', msgIDList: ['unread']),
      ], 'peer');
    }
    await tester.pump(Duration.zero);
    expect(changed, [
      equals({'read-a', 'read-b'})
    ]);
    expect(messages.last.isRead, isFalse);
    expect(timelineRefreshes, 0);
  });

  testWidgets('ordinary visibility and private burns publish their own rows',
      (tester) async {
    final ordinary = _message('ordinary');
    messages.add(ordinary);
    await tester.pump(Duration.zero);
    timelineRefreshes = 0;
    await receipts.markVisibleMessages(['ordinary']);
    await tester.pump(Duration.zero);
    expect(changed, [
      equals({'ordinary'})
    ]);
    expect(timelineRefreshes, 0);

    final private = _message('private', private: true);
    messages.add(private);
    await tester.pump(Duration.zero);
    timelineRefreshes = 0;
    changed.clear();
    await receipts.markRead(private);
    await tester.pump(Duration.zero);
    expect(changed, [
      equals({'private'})
    ]);
    expect(private.attachedInfoElem!.hasReadTime, greaterThan(0));
    expect(timelineRefreshes, 0);
  });

  testWidgets('late history receives confirmed read state with a row update',
      (tester) async {
    receipts.applyC2CReceipt([
      ReadReceiptInfo(userID: 'peer', msgIDList: ['late'])
    ], 'peer');
    await tester.pump(Duration.zero);
    expect(changed, isEmpty);
    messages.add(_message('late'));
    await tester.pump(Duration.zero);
    expect(messages.single.isRead, isTrue);
    expect(changed, [
      equals({'late'})
    ]);
    expect(timelineRefreshes, 1,
        reason: 'Only the structural insert refreshes');
  });

  for (final close in [false, true]) {
    testWidgets(
        'pending row refresh is discarded on ${close ? 'close' : 'account replacement'}',
        (tester) async {
      messages.add(_message('pending'));
      await tester.pump(Duration.zero);
      receipts.applyC2CReceipt([
        ReadReceiptInfo(userID: 'peer', msgIDList: ['pending'])
      ], 'peer');
      if (close) {
        receipts.close();
      } else {
        OpenIM.iMManager.userID = 'other';
      }
      await tester.pump(Duration.zero);
      expect(changed, isEmpty);
    });
  }
}
