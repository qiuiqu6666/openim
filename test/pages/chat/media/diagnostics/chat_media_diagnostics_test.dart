import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/chat/media/diagnostics/chat_media_diagnostics.dart';
import 'package:openim_common/openim_common.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_openim_sdk');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    Logger().sdkIsInited = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() {
    Logger().sdkIsInited = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test(
      'media diagnostics survive production Info filtering and redact SDK payload',
      () async {
    ChatMediaDiagnostics.record('upload_source',
        traceID: 'attempt',
        messageID: 'message',
        outcome: 'failed',
        elapsedMs: 123,
        error: PlatformException(
            code: '10017',
            message: '/private/photo.jpg token=secret',
            details: {'url': 'https://private.test/signed?token=secret'}));
    await Future<void>.delayed(Duration.zero);
    final args = calls.single.arguments as Map;
    expect(calls.single.method, 'logs');
    expect(args['logLevel'], 4);
    expect(args['operationID'], 'attempt');
    final text = args['msgs'] as String;
    final data = jsonDecode(text.substring('chat_media '.length)) as Map;
    expect(data['sdkCode'], 10017);
    expect(data['elapsedMs'], 123);
    expect(text, isNot(contains('private')));
    expect(text, isNot(contains('secret')));
  });
  test('diagnostic failure never changes the operation result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (_) async => throw PlatformException(code: 'closed'));
    expect(await ChatMediaTrace().run('load_asset', () async => 7), 7);
    await Future<void>.delayed(Duration.zero);
  });
  test('overlapping stages record their own duration and shared elapsed time',
      () async {
    final trace = ChatMediaTrace();
    await trace.run(
        'first', () => Future<void>.delayed(const Duration(milliseconds: 40)));
    await trace.run('second', () async {});
    await Future<void>.delayed(Duration.zero);
    final events = calls.map((call) => jsonDecode(
            (call.arguments['msgs'] as String).substring('chat_media '.length))
        as Map);
    final completed =
        events.where((event) => event['outcome'] == 'complete').toList();
    expect(completed.first['durationMs'], greaterThanOrEqualTo(30));
    expect(completed.last['durationMs'], lessThan(completed.last['elapsedMs']));
  });
  test('trace captures failures without swallowing the original exception',
      () async {
    final error = TimeoutException('private source path');
    final trace = ChatMediaTrace();
    await expectLater(trace.run('create_message', () async => throw error),
        throwsA(same(error)));
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(2));
    final event = calls.last.arguments['msgs'] as String;
    expect(event, contains('TimeoutException'));
    expect(event, isNot(contains('private source path')));
    expect(calls.first.arguments['operationID'],
        calls.last.arguments['operationID']);
  });
}
