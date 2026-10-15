import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/messages/revocation/chat_revocation_trace.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    Logger().sdkIsInited = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    Logger().sdkIsInited = false;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  ChatRevocationTrace trace({RevocationLog? log}) => ChatRevocationTrace(
      accountID: 'self',
      conversationID: 'sg_group',
      clientMsgID: 'message',
      seq: 72295,
      log: log);

  test('production sink uses Info level and a correlated native operation ID',
      () async {
    final t = trace();
    t.record('click');
    await Future<void>.delayed(Duration.zero);
    final args = calls.single.arguments as Map;
    expect(calls.single.method, 'logs');
    expect(args['logLevel'], 4);
    expect(args['operationID'], t.id);
    final event =
        jsonDecode((args['msgs'] as String).substring('chat_revoke '.length))
            as Map;
    expect(event['stage'], 'click');
    expect(event['seq'], 72295);
    expect(event['operationID'], t.id);
    expect(event.containsKey('timestamp'), isTrue);
  });

  test('unavailable SDK and rejected native log do not escape', () async {
    Logger().sdkIsInited = false;
    trace().record('click');
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    Logger().sdkIsInited = true;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (_) async => throw PlatformException(code: 'offline'));
    trace().record('click');
    await Future<void>.delayed(Duration.zero);
  });

  test('throwing diagnostic sink cannot interrupt the caller', () {
    expect(
        () => trace(log: (_) => throw StateError('log unavailable'))
            .record('click'),
        returnsNormally);
  });
}
