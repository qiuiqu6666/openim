import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/receipts/chat_read_receipts.dart';

void main() {
  testWidgets(
      '20 messages per second coalesce reads and cancel when no longer visible',
      (tester) async {
    OpenIM.iMManager.userID = 'self';
    var now = DateTime(2026);
    var reads = 0;
    final rows = <Message>[].obs;
    final receipt = ChatReadReceipts(
        messageList: rows,
        now: () => now,
        conversation: () => ConversationInfo(conversationID: 'g', groupID: 'g'),
        isClosed: () => false);
    const channel = MethodChannel('flutter_openim_sdk');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'markConversationMessageAsRead') reads++;
      return null;
    });
    addTearDown(() {
      receipt.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    for (var i = 1; i <= 1200; i++) {
      rows.value = [
        Message(
            clientMsgID: '$i',
            seq: i,
            sendID: 'peer',
            contentType: MessageType.text)
      ];
      await receipt.markVisibleMessages(['$i']);
      now = now.add(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(reads, inInclusiveRange(240, 241));
    final before = reads;
    rows.value = [
      Message(
          clientMsgID: 'unseen',
          seq: 1201,
          sendID: 'peer',
          contentType: MessageType.text)
    ];
    await receipt.markVisibleMessages(['unseen']);
    receipt.invalidateViewport();
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(reads, before);
    expect(rows.single.isRead, isNot(true));
    receipt.close();
  });
}
