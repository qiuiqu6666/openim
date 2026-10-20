import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/history/chat_local_display_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
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
