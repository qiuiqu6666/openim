import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');

  test('only an attested complete native snapshot can reach the first frame',
      () async {
    for (final response in [
      <String, dynamic>{'localSnapshot': true},
      <String, dynamic>{'localSnapshot': true, 'snapshotReady': false},
      <String, dynamic>{'snapshotReady': true},
      <String, dynamic>{
        'localSnapshot': true,
        'snapshotReady': true,
        'errCode': 500
      },
      <String, dynamic>{
        'localSnapshot': true,
        'snapshotReady': true,
        'errCode': 0
      },
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              channel,
              (call) async => jsonEncode({
                    ...response,
                    'messageList': [Message(clientMsgID: 'stored').toJson()],
                  }));
      final rows = await OpenIM.iMManager.messageManager
          .getLocalHistorySnapshot(conversationID: 'chat');
      expect(
          rows.length,
          response['localSnapshot'] == true &&
                  response['snapshotReady'] == true &&
                  response['errCode'] == 0
              ? 1
              : 0);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
}
