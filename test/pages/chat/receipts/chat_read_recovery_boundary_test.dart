import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/conversation_reads/conversation_read_request.dart';
import 'package:openim/pages/chat/receipts/chat_read_receipts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');

  for (final privateConversation in [false, true]) {
    test(
        'recovery excludes unseen, private and unsequenced rows; private chat: $privateConversation',
        () async {
      OpenIM.iMManager.userID = 'self';
      final messages = [
        Message(
            clientMsgID: 'unseen-older',
            seq: 1,
            sendID: 'peer',
            contentType: MessageType.text),
        Message(
            clientMsgID: 'seen',
            seq: 2,
            sendID: 'peer',
            contentType: MessageType.text),
        Message(
            clientMsgID: 'private',
            seq: 3,
            sendID: 'peer',
            contentType: MessageType.text,
            attachedInfoElem: AttachedInfoElem(isPrivateChat: true)),
        Message(
            clientMsgID: 'unsequenced',
            seq: 0,
            sendID: 'peer',
            contentType: MessageType.text),
        Message(
            clientMsgID: 'self-latest',
            seq: 4,
            sendID: 'self',
            contentType: MessageType.text),
      ].obs;
      final captured = <ConversationReadRequest>[];
      final conversation = ConversationInfo(
          conversationID: 'chat',
          unreadCount: 4,
          latestMsg: messages.last,
          isPrivateChat: privateConversation);
      final receipts = ChatReadReceipts(
          messageList: messages,
          conversation: () => conversation,
          isClosed: () => false,
          onConversationRead: captured.add);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() {
        receipts.close();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
      await receipts.markVisibleMessages(
          ['seen', 'private', 'unsequenced', 'self-latest']);
      expect(captured.single.retryMessageIDs,
          privateConversation ? isEmpty : ['seen']);
    });
  }
}
