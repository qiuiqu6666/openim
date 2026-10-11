import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/request_history/navigation/request_history_chat_opener.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const sdk = MethodChannel('flutter_openim_sdk');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(sdk, null));

  for (final type in [ConversationType.single, ConversationType.superGroup]) {
    test('SDK lookup type=$type cannot navigate after session becomes stale',
        () async {
      var current = true;
      final received = Completer<MethodCall>();
      final reply = Completer<String>();
      messenger.setMockMethodCallHandler(sdk, (call) {
        received.complete(call);
        return reply.future;
      });
      final opener = RequestHistoryChatOpener();
      final pending = opener.open(
          sourceID: 'target', sessionType: type, isCurrent: () => current);
      final call = await received.future;
      expect(call.method, 'getOneConversation');
      expect(call.arguments['sourceID'], 'target');
      expect(call.arguments['sessionType'], type);
      // A second tap must not start another lookup while the first is pending.
      await opener.open(
          sourceID: 'target', sessionType: type, isCurrent: () => current);
      current = false;
      reply.complete(jsonEncode(
          {'conversationID': 'conversation', 'conversationType': type}));
      // There is intentionally no navigator. Stale replies must stop here.
      await pending;
    });
  }
  test('empty or inactive targets never query the SDK', () async {
    messenger.setMockMethodCallHandler(
        sdk, (call) async => fail('Unexpected lookup'));
    final opener = RequestHistoryChatOpener();
    await opener.open(sourceID: null, sessionType: 1, isCurrent: () => true);
    await opener.open(sourceID: ' ', sessionType: 1, isCurrent: () => true);
    await opener.open(sourceID: 'peer', sessionType: 1, isCurrent: () => false);
  });
}
