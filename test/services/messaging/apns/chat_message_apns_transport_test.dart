import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/chat_message_sender.dart';
import 'package:openim/services/favorite_send_coordinator.dart';
import 'package:openim/services/messaging/message_send_session.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final sent = <Map<String, dynamic>>[];
  Completer<void>? lookupGate;
  var lookups = 0;
  var failLookup = false;
  var groups = <Map<String, dynamic>>[];

  Future<void> credentials({String token = 'test-im-token'}) async {
    await DataSp.putLoginCertificate(LoginCertificate.fromJson({
      'userID': '@owner',
      'imToken': token,
      'chatToken': 'test-chat-token',
    }));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    await credentials();
    OpenIM.iMManager.userID = '@owner';
    sent.clear();
    lookupGate = null;
    lookups = 0;
    failLookup = false;
    groups = [
      {'groupID': '@destination', 'groupType': GroupType.work}
    ];
    messenger.setMockMethodCallHandler(channel, (call) async {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      switch (call.method) {
        case 'getGroupsInfo':
          expect(args['groupIDList'], ['@destination']);
          lookups++;
          await lookupGate?.future;
          if (failLookup) {
            throw PlatformException(code: 'GROUP_LOOKUP_UNAVAILABLE');
          }
          return jsonEncode(groups);
        case 'createForwardMessage':
          final message = Map<String, dynamic>.from(args['message'] as Map)
            ..['clientMsgID'] = 'new-forward-id';
          return jsonEncode(message);
        case 'sendMessage':
          sent.add(args);
          return jsonEncode(Map<String, dynamic>.from(args['message'] as Map)
            ..['status'] = MessageStatus.succeeded);
        default:
          throw StateError('Unexpected SDK operation ${call.method}');
      }
    });
  });

  tearDown(() {
    if (lookupGate?.isCompleted == false) lookupGate!.complete();
    messenger.setMockMethodCallHandler(channel, null);
    OpenIM.iMManager.userID = '';
  });

  // SDK-created and received messages use fromJson. The bare Message
  // constructor's const exMap cannot be passed through SDK Utils.cleanMap.
  Message message({int? sourceType}) => Message.fromJson({
        'clientMsgID': 'created-message-id',
        'sendID': '@original-author',
        'groupID': '@source-group',
        'sessionType': sourceType,
        'contentType': MessageType.text,
        'textElem': {'content': 'private-message-content'},
      });

  Map<String, dynamic> extension() {
    final push =
        Map<String, dynamic>.from(sent.single['offlinePushInfo'] as Map);
    expect(push['title'], '99CHAT');
    expect(push['desc'], '你收到了一条新消息');
    expect(push['iOSBadgeCount'], isTrue);
    expect(push['iOSPushSound'], 'default');
    expect(jsonEncode(push), isNot(contains('private-message-content')));
    expect(sent.single['isOnlineOnly'], isFalse);
    return Map<String, dynamic>.from(jsonDecode(push['ex'] as String) as Map);
  }

  test(
      'actual SDK private send uses current SDK owner and a generic APNs alert',
      () async {
    await ChatMessageSender().sendRaw(message(sourceType: 3),
        const FavoriteTarget(conversationID: 'si_peer', userID: '@peer'));
    expect(lookups, 0);
    expect(sent.single['userID'], '@peer');
    expect(sent.single['groupID'], '');
    expect(extension(), {
      'version': 1,
      'type': 'chat_message',
      'sessionType': 1,
      'sendID': '@owner',
      'groupID': '',
    });
  });

  test(
      'SDK forwarding targets the real destination group rather than source type',
      () async {
    final forwarded = await OpenIM.iMManager.messageManager
        .createForwardMessage(message: message(sourceType: 1));
    await ChatMessageSender().sendRaw(
        forwarded,
        const FavoriteTarget(
            conversationID: 'sg_destination', groupID: '@destination'));
    expect(sent.single['groupID'], '@destination');
    expect(sent.single['userID'], '');
    expect(sent.single['message']['clientMsgID'], 'new-forward-id');
    expect(lookups, 1);
    final data = extension();
    expect(data['sessionType'], 3);
    expect(data['groupID'], '@destination');
    expect(data['sendID'], '@owner');
  });

  test(
      'a known legacy destination retains SDK type 2 without querying another chat',
      () async {
    await ChatMessageSender().sendRaw(
        message(sourceType: 3),
        const FavoriteTarget(
            conversationID: 'gr_destination',
            groupID: '@destination',
            sessionType: 2));
    expect(lookups, 0);
    expect(extension()['sessionType'], 2);
  });

  for (final unavailable in ['failure', 'wrong_group', 'unknown_type']) {
    test(
        'SDK group metadata $unavailable preserves delivery with no guessed APNs target',
        () async {
      failLookup = unavailable == 'failure';
      if (unavailable == 'wrong_group') {
        groups = [
          {'groupID': '@other', 'groupType': GroupType.work}
        ];
      }
      if (unavailable == 'unknown_type') {
        groups = [
          {'groupID': '@destination', 'groupType': 99}
        ];
      }
      await ChatMessageSender().sendRaw(
          message(sourceType: 1),
          const FavoriteTarget(
              conversationID: 'sg_destination', groupID: '@destination'));
      expect(sent, hasLength(1));
      final push =
          Map<String, dynamic>.from(sent.single['offlinePushInfo'] as Map);
      expect(push['ex'], isNull);
      expect(push['title'], '99CHAT');
      expect(push['desc'], '你收到了一条新消息');
      expect(sent.single['isOnlineOnly'], isFalse);
    });
  }

  for (final change in ['account', 'token', 'service']) {
    test(
        '$change switch while destination metadata is pending cannot send the old action',
        () async {
      lookupGate = Completer<void>();
      final request = ChatMessageSender().sendRaw(
          message(),
          const FavoriteTarget(
              conversationID: 'sg_destination', groupID: '@destination'));
      final rejected =
          expectLater(request, throwsA(isA<MessageSendSessionChanged>()));
      await Future<void>.delayed(Duration.zero);
      expect(lookups, 1);
      if (change == 'account') OpenIM.iMManager.userID = '@new-owner';
      if (change == 'token') {
        await credentials(token: 'new-im-token');
        failLookup = true; // A metadata fallback must still respect the fence.
      }
      if (change == 'service') {
        await DataSp.putServerConfig({'apiUrl': 'https://new-im.example.test'});
      }
      lookupGate!.complete();
      await rejected;
      expect(sent, isEmpty);
    });
  }
}
