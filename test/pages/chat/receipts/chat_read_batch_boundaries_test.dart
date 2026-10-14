import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/receipts/chat_read_receipts.dart';

Message _message(int seq, {bool private = false}) => Message(
      clientMsgID: 'm$seq',
      seq: seq,
      sendID: 'peer',
      contentType: MessageType.text,
      attachedInfoElem: private ? AttachedInfoElem(isPrivateChat: true) : null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  late RxList<Message> messages;
  late ChatReadReceipts receipts;
  late DateTime now;
  late bool active, readable, fail;
  late List<String> methods;

  setUp(() {
    OpenIM.iMManager.userID = 'self';
    messages = <Message>[].obs;
    now = DateTime(2026);
    active = readable = true;
    fail = false;
    methods = [];
    receipts = ChatReadReceipts(
      messageList: messages,
      now: () => now,
      conversation: () => ConversationInfo(conversationID: 'single'),
      isClosed: () => false,
      isActive: () => active,
      canReadConversation: () => readable,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      if (fail) throw PlatformException(code: 'offline');
      return null;
    });
  });

  tearDown(() {
    receipts.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> show(int sequence, {bool private = false}) async {
    final message = _message(sequence, private: private);
    messages.add(message);
    await receipts.markVisibleMessages([message.clientMsgID!]);
  }

  testWidgets('private content bypasses an ordinary pending batch',
      (tester) async {
    await show(1);
    await show(2);
    expect(methods, ['markConversationMessageAsRead']);
    await show(3, private: true);
    expect(methods, [
      'markConversationMessageAsRead',
      'markConversationMessageAsRead',
      'markMessagesAsReadByMsgID',
    ]);
    expect(messages.last.attachedInfoElem!.hasReadTime, greaterThan(0));
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(methods, hasLength(3),
        reason: 'The old ordinary timer was cancelled');
  });

  for (final boundary in ['covered', 'entrance', 'scrolled away']) {
    testWidgets('deferred single-chat read rechecks $boundary', (tester) async {
      await show(1);
      await show(2);
      expect(methods, hasLength(1));
      if (boundary == 'covered') {
        active = false;
      } else if (boundary == 'entrance') {
        readable = false;
      } else {
        await receipts.markVisibleMessages(['m1'], atLatest: false);
      }
      now = now.add(ChatReadReceipts.viewportReadInterval);
      await tester.pump(ChatReadReceipts.viewportReadInterval);
      expect(methods, hasLength(1));
      expect(messages.last.isRead, isNot(true));
      active = readable = true;
      receipts.invalidateViewport();
      await receipts.markVisibleMessages(['m2']);
      await tester.pump(Duration.zero);
      expect(methods, hasLength(2));
      expect(messages.last.isRead, isTrue);
    });
  }

  testWidgets('leaving immediately flushes the final painted batched target',
      (tester) async {
    await show(1);
    await show(2);
    expect(methods, hasLength(1));
    active = false;
    receipts.clearUnreadCount(leaving: true);
    receipts.close();
    await tester.pump(Duration.zero);
    expect(methods, hasLength(2));
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(methods, hasLength(2));
    expect(messages.last.isRead, isNot(true), reason: 'No disposed row writes');
  });

  testWidgets('failed read is rate limited and does not retry itself forever',
      (tester) async {
    fail = true;
    await show(1);
    for (var frame = 0; frame < 60; frame++) {
      await receipts.markVisibleMessages(['m1']);
    }
    expect(methods, hasLength(1));
    now = now.add(ChatReadReceipts.viewportReadInterval);
    await tester.pump(ChatReadReceipts.viewportReadInterval);
    expect(methods, hasLength(2));
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(methods, hasLength(2));
    fail = false;
    await receipts.markVisibleMessages(['m1']);
    await tester.pump(Duration.zero);
    expect(methods, hasLength(3));
    expect(messages.single.isRead, isTrue);
  });
}
