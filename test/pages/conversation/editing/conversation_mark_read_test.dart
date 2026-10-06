import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim/core/im_callback.dart';
import 'package:openim/pages/conversation/conversation_logic.dart';
import 'package:openim/pages/home/home_logic.dart';

class _App extends GetxController implements AppController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IM extends GetxController with IMCallback implements IMController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  void onClose() {
    close();
    super.onClose();
  }
}

class _Home extends GetxController implements HomeLogic {
  @override
  final conversationsAtFirstPage = <ConversationInfo>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationInfo _conversation({
  String id = 'chat',
  int unread = 3,
  int time = 1,
  String messageId = 'message-1',
  int sequence = 1,
}) =>
    ConversationInfo(
      conversationID: id,
      userID: id,
      unreadCount: unread,
      latestMsgSendTime: time,
      draftTextTime: 0,
      latestMsg: Message(clientMsgID: messageId, seq: sequence, sendTime: time),
    );

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  late List<MethodCall> calls;
  late List<Completer<void>> replies;
  late List<ConversationLogic> controllers;

  setUp(() {
    Get.testMode = true;
    OpenIM.iMManager.userID = 'self';
    Get.put<AppController>(_App());
    Get.put<IMController>(_IM());
    Get.put<HomeLogic>(_Home());
    calls = [];
    replies = [];
    controllers = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, (call) {
      expect(call.method, 'markConversationMessageAsRead');
      calls.add(call);
      final reply = Completer<void>();
      replies.add(reply);
      return reply.future;
    });
  });

  tearDown(() {
    for (final logic in controllers) {
      logic.onClose();
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(sdk, null);
    Get.reset();
    OpenIM.iMManager.userID = 'self';
  });

  ConversationLogic createLogic() {
    // Direct construction avoids Get.put invoking the real SDK subscriptions.
    final logic = ConversationLogic();
    controllers.add(logic);
    return logic;
  }

  test(
      'mark read calls the SDK with the selected conversation and clears on ack',
      () async {
    final logic = createLogic();
    final selected = _conversation();
    final unrelated = _conversation(id: 'other-chat', unread: 7);
    logic.list.addAll([selected, unrelated]);

    final pending = logic.markConversationRead(selected);
    await _flush();
    expect(calls, hasLength(1));
    final arguments = Map<String, dynamic>.from(calls.single.arguments as Map);
    expect(arguments['ManagerName'], 'conversationManager');
    expect(arguments['conversationID'], 'chat');
    expect(arguments['operationID'], isA<String>());
    expect(arguments['operationID'], isNotEmpty);
    expect(selected.unreadCount, 3);

    replies.single.complete();
    await pending;
    expect(logic.list.first.unreadCount, 0);
    expect(unrelated.unreadCount, 7);
  });

  test('SDK failure propagates without clearing unread messages', () async {
    final logic = createLogic();
    final selected = _conversation();
    logic.list.add(selected);

    final pending = logic.markConversationRead(selected);
    await _flush();
    final failure = expectLater(pending, throwsA(isA<PlatformException>()));
    replies.single.completeError(PlatformException(code: 'SDK_FAILURE'));
    await failure;

    expect(logic.list.single.unreadCount, 3);
    expect(selected.unreadCount, 3);
  });

  test('a late ack after close cannot restore or mutate the closed page',
      () async {
    final logic = createLogic();
    final selected = _conversation();
    logic.list.add(selected);

    final pending = logic.markConversationRead(selected);
    await _flush();
    logic.onClose();
    controllers.remove(logic);
    replies.single.complete();
    await pending;

    expect(logic.list, isEmpty);
    expect(selected.unreadCount, 3);
  });

  test('a late ack cannot modify a replacement account with the same chat ID',
      () async {
    final logic = createLogic();
    final selected = _conversation();
    logic.list.add(selected);

    final pending = logic.markConversationRead(selected);
    await _flush();
    OpenIM.iMManager.userID = 'other-account';
    final replacement = _conversation(unread: 8);
    logic.list.assignAll([replacement]);
    replies.single.complete();
    await pending;

    expect(logic.list.single, same(replacement));
    expect(replacement.unreadCount, 8);
    expect(selected.unreadCount, 3);
  });

  test('clearing the page invalidates a pending mark read ack', () async {
    final logic = createLogic();
    final selected = _conversation();
    logic.list.add(selected);

    final pending = logic.markConversationRead(selected);
    await _flush();
    logic.clearConversations();
    final replacement = _conversation(unread: 6);
    logic.list.add(replacement);
    replies.single.complete();
    await pending;

    expect(logic.list.single, same(replacement));
    expect(replacement.unreadCount, 6);
    expect(selected.unreadCount, 3);
  });

  test('an inactive account is rejected before any SDK request', () async {
    final logic = createLogic();
    final selected = _conversation();
    logic.list.add(selected);
    OpenIM.iMManager.userID = 'other-account';

    await expectLater(
        logic.markConversationRead(selected), throwsA(isA<StateError>()));
    expect(calls, isEmpty);
    expect(replies, isEmpty);
    expect(selected.unreadCount, 3);
  });

  test('a conversation already marked read does not call the SDK', () async {
    final logic = createLogic();
    final selected = _conversation(unread: 0);
    logic.list.add(selected);

    await logic.markConversationRead(selected);
    expect(calls, isEmpty);
    expect(selected.unreadCount, 0);
  });

  for (final newer in ['timestamp', 'message ID', 'sequence', 'unread count']) {
    test('a newer $newer received during the SDK request stays unread',
        () async {
      final logic = createLogic();
      final selected = _conversation();
      logic.list.add(selected);

      final pending = logic.markConversationRead(selected);
      await _flush();
      final incoming = _conversation(
        time: newer == 'timestamp' ? 2 : 1,
        messageId: newer == 'message ID' ? 'message-2' : 'message-1',
        sequence: newer == 'sequence' ? 2 : 1,
        unread: newer == 'unread count' ? 4 : 3,
      );
      logic.onChanged([incoming]);
      replies.single.complete();
      await pending;

      expect(logic.list.single, same(incoming));
      expect(incoming.unreadCount, newer == 'unread count' ? 4 : 3);
    });
  }
}
