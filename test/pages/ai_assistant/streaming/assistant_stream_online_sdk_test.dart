import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/core/controller/app_controller.dart';
import 'package:openim/core/controller/im_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/chat/chat_entry_sdk.dart';

class _NotificationApp extends EntryTestApp {
  final notifications = <Message>[];

  @override
  Future<void> showNotification(Message message,
      {bool showNotification = true}) async {
    notifications.add(message);
  }
}

class _OnlineIM extends IMController {
  final invitations = <SignalingInfo>[];

  @override
  void receiveNewInvitation(SignalingInfo info) => invitations.add(info);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _NotificationApp app;
  late List<String> nativeCalls;
  _OnlineIM? controller;

  Future<void> receiveOnline(Message message) async {
    final reply = Completer<ByteData?>();
    // Exercise the native envelope, SDK decoder and registered production bridge.
    // ignore: deprecated_member_use
    await messenger.handlePlatformMessage(
      channel.name,
      channel.codec.encodeMethodCall(MethodCall('advancedMsgListener', {
        'type': 'onRecvOnlineOnlyMessage',
        'data': {'message': jsonEncode(message.toJson())},
      })),
      reply.complete,
    );
    final response = await reply.future;
    if (response != null) channel.codec.decodeEnvelope(response);
  }

  setUp(() async {
    Get.testMode = true;
    app = _NotificationApp();
    Get.put<AppController>(app);
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Config.cachePath = 'test-cache/';
    nativeCalls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      nativeCalls.add(call.method);
      return call.method == 'initSDK' ? true : null;
    });
  });

  tearDown(() {
    // Do not leave the singleton SDK pointing to a closed test controller.
    OpenIM.iMManager.messageManager.msgListener = OnAdvancedMsgListener();
    controller?.onClose();
    controller = null;
    Logger().sdkIsInited = false;
    messenger.setMockMethodCallHandler(channel, null);
    Get.reset();
  });

  testWidgets(
      'native online-only deltas bypass signaling and notices while typing and calls remain supported',
      (tester) async {
    await tester.pumpWidget(GetMaterialApp(home: const Scaffold()));
    await tester.runAsync(() async {
      // Call initOpenIM directly so its real listener is tested without starting
      // the live-call lifecycle or authenticating against a server.
      final im = controller = _OnlineIM();
      final received = <Message>[];
      im.onRecvNewMessage = received.add;
      final initialized = im.initializedSubject.first;
      im.initOpenIM();
      expect(await initialized, isTrue);
      expect(nativeCalls, contains('setAdvancedMsgListener'));

      final validData = jsonEncode({
        'streamID': 'turn-1',
        'index': 0,
        'text': '在线片段',
        'end': false,
      });
      for (final data in [validData, '{']) {
        await receiveOnline(Message(
          clientMsgID: 'delta-${received.length}',
          sendID: 'assistant',
          recvID: 'self',
          sessionType: ConversationType.single,
          contentType: MessageType.custom,
          customElem: CustomElem(description: 'assistantStream', data: data),
        ));
      }
      expect(received.map((message) => message.customElem?.data),
          [validData, '{']);
      expect(im.invitations, isEmpty);
      expect(app.notifications, isEmpty);

      await receiveOnline(Message(
          contentType: MessageType.typing,
          sendID: 'assistant',
          recvID: 'self',
          sessionType: ConversationType.single,
          typingElem: TypingElem(msgTips: 'yes')));
      expect(received.last.contentType, MessageType.typing);
      expect(received.last.typingElem?.msgTips, 'yes');

      await receiveOnline(Message(
          contentType: MessageType.custom,
          customElem: CustomElem(
              data: jsonEncode({
            'customType': CustomMessageType.callingInvite,
            'data': InvitationInfo(
                    inviterUserID: 'caller',
                    inviteeUserIDList: ['self'],
                    sessionType: ConversationType.single,
                    roomID: 'call-room',
                    mediaType: 'audio')
                .toJson(),
          }))));
      expect(im.invitations.single.userID, 'caller');
      expect(received, hasLength(3));
      expect(app.notifications, isEmpty);
    });
  });
}
