import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/messages/chat_delivery_controller.dart';
import 'package:openim/pages/chat/messages/chat_message_actions.dart';
import 'package:openim/pages/chat/messages/forwarding/chat_forwarding_controller.dart';
import 'package:openim/services/favorite_send_coordinator.dart';

Message forwardingSource(String id,
        {int time = 1,
        int type = MessageType.text,
        int status = MessageStatus.succeeded,
        bool private = false}) =>
    Message.fromJson({
      'clientMsgID': id,
      'sendTime': time,
      'sendID': 'original-sender',
      'senderNickname': 'Original sender',
      'contentType': type,
      'status': status,
      'textElem': {'content': 'Text $id'},
      if (private) 'attachedInfoElem': {'isPrivateChat': true},
    });

Message forwardingReceipt(Message message) => Message.fromJson({
      ...message.toJson(),
      'status': MessageStatus.succeeded,
    });

class ForwardingFixture {
  ForwardingFixture() {
    delivery = ChatDeliveryController(
        messageList: timeline,
        accountID: 'self',
        currentAccountID: () => account,
        conversation: () => ConversationInfo(
            conversationID: 'current-chat', userID: 'current-peer'),
        isClosed: () => closed,
        groupStatus: () => null,
        scrollBottom: () {},
        resetInput: (_) => inputResets++,
        sendRaw: (message, target) async {
          sends.add((message: message, target: target));
          return onSend == null
              ? forwardingReceipt(message)
              : await onSend!(message, target);
        });
    final actions = ChatMessageActions(
        conversationID: () => 'current-chat',
        removeMessage: (_) {},
        isClosed: () => closed);
    controller = ChatForwardingController(
        delivery: delivery,
        messages: () => timeline,
        isClosed: () => closed,
        isGroupChat: () => false,
        nickname: () => 'Current chat',
        faceUrl: () => '',
        closeToolbox: () {},
        canForward: (message) =>
            policy?.call(message) ?? actions.canForward(message),
        selectContacts: (description) async {
          pickerDescriptions.add(description);
          return onPick == null
              ? {
                  'checkedList': [UserInfo(userID: 'target-user')]
                }
              : await onPick!();
        },
        createForward: (message) async {
          originals.add(message.clientMsgID!);
          return onCreate == null
              ? forwardingSource('forward-${++_serial}',
                  status: MessageStatus.sending)
              : await onCreate!(message);
        },
        createMerger: (
            {required messageList,
            required title,
            required summaryList}) async {
          merges.add((
            ids: messageList.map((message) => message.clientMsgID!).toList(),
            title: title,
            summary: List<String>.of(summaryList)
          ));
          return onMerge == null
              ? forwardingSource('merge-${++_serial}',
                  type: MessageType.merger, status: MessageStatus.sending)
              : await onMerge!();
        },
        showToast: toasts.add,
        onForwardNeedsReview: () => reviewRequests++);
  }

  final timeline = <Message>[].obs;
  final pickerDescriptions = <String>[];
  final originals = <String>[];
  final sends = <({Message message, FavoriteTarget target})>[];
  final merges = <({List<String> ids, String title, List<String> summary})>[];
  final toasts = <String>[];
  late final ChatDeliveryController delivery;
  late final ChatForwardingController controller;
  String account = 'self';
  bool closed = false, _disposed = false;
  int inputResets = 0, reviewRequests = 0, _serial = 0;
  bool Function(Message)? policy;
  Future<dynamic> Function()? onPick;
  Future<Message> Function(Message)? onCreate;
  Future<Message> Function()? onMerge;
  Future<Message> Function(Message, FavoriteTarget)? onSend;

  Future<bool> forward(List<Message> selection, {required bool merged}) {
    timeline.assignAll(selection);
    return controller.forwardMessages(selection, merged: merged);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    delivery.close();
  }
}

Future<void> flushForwarding() async {
  for (var turn = 0; turn < 4; turn++) {
    await Future<void>.delayed(Duration.zero);
  }
}
