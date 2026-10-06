import 'dart:async';
import 'dart:convert';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_live/openim_live.dart';

class EntryTestApp extends GetxController implements AppController {
  @override
  Future<void> onApplicationSessionReady({bool authenticated = false}) async {}

  @override
  void markDeviceSyncUserActivity() {}

  @override
  Future<void> onNotificationSessionReady({bool authenticated = false}) async {}

  @override
  Future<void> showNotification(Message message,
      {bool showNotification = true}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EntryTestIM extends GetxController
    with IMCallback
    implements IMController {
  @override
  final userInfo = UserFullInfo(globalRecvMsgOpt: 0).obs;
  @override
  Function(SignalingMessageEvent)? onSignalingMessage;

  @override
  void onClose() {
    close();
    super.onClose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EntryTestConversation extends GetxController
    implements ConversationLogic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EntryTestCache extends GetxController implements CacheController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class EntryHistoryCall {
  EntryHistoryCall(this.arguments);
  final Map<String, dynamic> arguments;
  final result = Completer<String>();

  void complete(List<Message> messages, {bool isEnd = true}) {
    if (result.isCompleted) return;
    result.complete(jsonEncode(
        AdvancedMessage(messageList: messages, isEnd: isEnd, errCode: 0)
            .toJson()));
  }
}
