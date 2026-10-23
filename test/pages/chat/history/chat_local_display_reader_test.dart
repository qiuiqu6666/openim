import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_local_display_reader.dart';
import 'message_window_ingress_test.dart' show window;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  setUp(() {
    OpenIM.iMManager.userID = 'display-test';
    MessageWindowCache.shared.invalidate();
  });
  tearDown(() {
    MessageWindowCache.shared.invalidate();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final type in [MessageType.picture, MessageType.video]) {
    test('first display uses persisted recall instead of stale media $type',
        () async {
      var calls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls++;
        expect(call.method, 'getLocalHistorySnapshot');
        final verified = call.arguments['window'] == true;
        return jsonEncode({
          'localSnapshot': true,
          'snapshotReady': true,
          if (verified) 'window': window(1).toJson(),
          'messageList': [
            {
              'clientMsgID': 'recalled-media',
              'seq': 1,
              'contentType':
                  verified ? MessageType.revokeMessageNotification : type,
              if (verified)
                'notificationElem': {
                  'detail': '{"clientMsgID":"recalled-media"}'
                },
              if (!verified && type == MessageType.picture) 'pictureElem': {},
              if (!verified && type == MessageType.video) 'videoElem': {},
            }
          ],
        });
      });
      for (var entry = 0; entry < 2; entry++) {
        final rows = await readChatLocalDisplay(
            ConversationInfo(conversationID: 'chat'));
        expect(rows.single.contentType, MessageType.revokeMessageNotification);
        expect(rows.single.pictureElem, isNull);
        expect(rows.single.videoElem, isNull);
      }
      expect(calls, 1); // Safe native window reused on immediate reentry.
    });
  }

  for (final proof in ['legacy', 'incomplete', 'wrong-conversation']) {
    test('unsafe $proof snapshot cannot paint an old media body', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              channel,
              (_) async => jsonEncode({
                    'localSnapshot': true,
                    'snapshotReady': true,
                    if (proof != 'legacy')
                      'window': {
                        ...window(1,
                                id: proof == 'wrong-conversation'
                                    ? 'other'
                                    : 'chat')
                            .toJson(),
                        if (proof == 'incomplete') 'publishable': false,
                      },
                    'messageList': [
                      {'clientMsgID': 'old', 'contentType': MessageType.picture}
                    ],
                  }));
      expect(
          await readChatLocalDisplay(ConversationInfo(conversationID: 'chat')),
          isEmpty);
    });
  }
  test('private conversation displays only ordinary local rows', () async {
    final manager = OpenIM.iMManager;
    manager.userID = 'display-test';
    addTearDown(() {
      manager.userID = '';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final methods = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      expect(call.method, 'searchLocalMessages');
      expect(call.arguments['filter']['conversationID'], 'chat');
      expect(call.arguments['filter']['count'], 40);
      return jsonEncode({
        'searchResultItems': [
          {
            'conversationID': 'chat',
            'messageList': [
              {'clientMsgID': 'ordinary'},
              {
                'clientMsgID': 'private',
                'attachedInfoElem': {'isPrivateChat': true}
              }
            ]
          },
          {
            'conversationID': 'other',
            'messageList': [
              {'clientMsgID': 'wrong-chat'}
            ]
          }
        ]
      });
    });
    final rows = await readChatLocalDisplay(
        ConversationInfo(conversationID: 'chat', isPrivateChat: true));
    expect(rows.map((m) => m.clientMsgID), ['ordinary']);
    expect(methods, ['searchLocalMessages']);
  });
}
