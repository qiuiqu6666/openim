import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/fund/diagnostics/wallet_load_log.dart';
import 'package:openim_common/src/utils/logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> lines;
  late DebugPrintCallback original;
  setUp(() {
    lines = [];
    original = debugPrint;
    debugPrint =
        (String? message, {int? wrapWidth}) => lines.add(message ?? '');
  });
  tearDown(() => debugPrint = original);

  test('payment status logs codes and bool without credentials or payloads',
      () {
    final trace = WalletLoadLog.request(
      method: 'GET',
      path: '/chat/fund/pay-password',
      url:
          'https://secret-user:secret-pass@chat.test/chat/fund/pay-password?token=secret-token',
      operationID: 'test-operation',
      hasToken: true,
    )!;
    trace.response(
        Response(requestOptions: RequestOptions(), statusCode: 200, data: {
      'errCode': 0,
      'errMsg': 'secret-token',
      'data': {
        'set': true,
        'password': 'secret-pin',
        'balance': 'secret-balance',
      }
    }));
    trace.finish('end');
    final output = lines.join('\n');
    expect(output, isNot(contains('secret-')));
    expect(output, contains('"httpStatus":200'));
    expect(output, contains('"errCode":0'));
    expect(output, contains('"passwordSet":true'));
    expect(output, contains('"setPresent":true'));
    expect(output, contains('"operationID":"test-operation"'));
    expect(lines, hasLength(2));
  });

  test('diagnostics distinguish omitted default from a malformed set value',
      () {
    for (final payload in [
      <String, dynamic>{},
      {'set': null}
    ]) {
      final trace = WalletLoadLog.request(
          method: 'GET',
          url: 'https://chat.test',
          path: '/chat/fund/pay-password',
          operationID: 'shape',
          hasToken: true)!;
      trace.response(Response(
          requestOptions: RequestOptions(),
          statusCode: 200,
          data: {'errCode': 0, 'data': payload}));
    }
    final responses = lines
        .map(
            (line) => jsonDecode(line.substring('[WalletLoad] '.length)) as Map)
        .where((entry) => entry['event'] == 'response')
        .toList();
    expect(responses[0]['dataEmpty'], isTrue);
    expect(responses[0]['setPresent'], isFalse);
    expect(responses[1]['dataEmpty'], isFalse);
    expect(responses[1]['setPresent'], isTrue);
    expect(responses[1]['setIsBool'], isFalse);
  });

  test('HTTP failure logs classification without raw exception or body', () {
    final trace = WalletLoadLog.start('http')!;
    final request =
        RequestOptions(path: '/secret-path', data: {'password': 'secret-pin'});
    trace.error(DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        message: 'secret-token',
        response: Response(
            requestOptions: request,
            statusCode: 503,
            data: {'errCode': 500, 'errMsg': 'secret-balance'})));
    trace.finish('end');
    final output = lines.join('\n');
    expect(output, isNot(contains('secret-')));
    expect(output, contains('"networkType":"badResponse"'));
    expect(output, contains('"httpStatus":503'));
    expect(output, contains('"errCode":500'));
  });

  test('slow request reports once and completion cancels its timer', () {
    fakeAsync((clock) {
      final trace = WalletLoadLog.start('entry', watchPending: true)!;
      clock.elapse(const Duration(seconds: 5));
      clock.elapse(const Duration(seconds: 30));
      final events = lines.map((line) =>
          (jsonDecode(line.substring('[WalletLoad] '.length)) as Map)['event']);
      expect(events.where((event) => event == 'pending'), hasLength(1));
      trace.finish('cancelled');
      final next = WalletLoadLog.start('entry', watchPending: true)!;
      next.finish('cancelled');
      final count = lines.length;
      clock.elapse(const Duration(seconds: 6));
      expect(lines, hasLength(count));
    });
  });

  test(
      'unrelated writes are excluded and a failing console never breaks callers',
      () {
    expect(
        WalletLoadLog.request(
            method: 'PUT',
            url: 'https://chat.test',
            path: '/chat/fund/orders',
            operationID: 'write',
            hasToken: true),
        isNull);
    expect(lines, isEmpty);
    debugPrint =
        (String? message, {int? wrapWidth}) => throw StateError('console');
    final trace = WalletLoadLog.start('entry')!;
    expect(() => trace.error(StateError('private data')), returnsNormally);
    expect(() => trace.finish('end'), returnsNormally);
    final password = WalletLoadLog.passwordSetup();
    expect(() => password.error(StateError('secret-pin')), returnsNormally);
    expect(() => password.finish('failed'), returnsNormally);
  });

  test('password write logs HTTP failure without password, token, or raw body',
      () {
    final trace = WalletLoadLog.request(
      method: 'PUT',
      path: '/chat/fund/pay-password',
      url:
          'https://secret-user:secret-pass@chat.test/chat/fund/pay-password?token=secret-token',
      operationID: 'payment-operation',
      hasToken: true,
    )!;
    final request = RequestOptions(
        path: '/chat/fund/pay-password',
        data: {'password': 'secret-pin', 'verifyCode': 'secret-code'},
        headers: {'token': 'secret-token'});
    trace.error(DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        message: 'secret-native-error',
        response: Response(
            requestOptions: request,
            statusCode: 503,
            data: {'errCode': 20030, 'errMsg': 'secret-response'})));
    trace.finish('end');
    final output = lines.join('\n');
    expect(lines.every((line) => line.startsWith('[TradePassword]')), isTrue);
    expect(output, contains('"httpStatus":503'));
    expect(output, contains('"errCode":20030'));
    expect(output, contains('"networkType":"badResponse"'));
    expect(output, contains('"operationID":"payment-operation"'));
    expect(output, contains('"server":"https://chat.test:443"'));
    expect(output, contains('"elapsedMs":'));
    expect(output, isNot(contains('secret-')));
  });

  test('password response parsing errors remain visible after HTTP success',
      () {
    final trace = WalletLoadLog.request(
        method: 'PUT',
        url: 'https://chat.test',
        path: '/chat/fund/pay-password',
        operationID: 'parse',
        hasToken: false)!;
    trace.response(Response(
        requestOptions: RequestOptions(),
        statusCode: 200,
        data: {'unexpected': 'secret-response'}));
    trace.error(const FormatException('secret-body'));
    trace.finish('end');
    expect(lines.join('\n'), contains('"errorType":"FormatException"'));
    expect(lines.join('\n'), isNot(contains('secret-')));
    expect(lines, hasLength(4));
  });

  test('closing password setup stops pending diagnostics', () {
    fakeAsync((clock) {
      final trace = WalletLoadLog.passwordSetup();
      clock.elapse(const Duration(seconds: 5));
      trace.finish('view_closed');
      final count = lines.length;
      trace.finish('success');
      clock.elapse(const Duration(seconds: 30));
      expect(lines, hasLength(count));
      expect(lines.where((line) => line.contains('"event":"pending"')),
          hasLength(1));
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test('password diagnostics reach SDK logs and tolerate SDK failures',
      () async {
    const channel = MethodChannel('flutter_openim_sdk');
    final calls = <MethodCall>[];
    final wasInitialized = Logger().sdkIsInited;
    Logger().sdkIsInited = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      throw PlatformException(code: 'logger unavailable');
    });
    addTearDown(() {
      Logger().sdkIsInited = wasInitialized;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    final trace = WalletLoadLog.passwordSetup();
    trace.error((20030, 'secret-backend-message'));
    trace.finish('failed');
    await Future<void>.delayed(Duration.zero);
    expect(calls, hasLength(3));
    expect(calls.every((call) => call.method == 'logs'), isTrue);
    for (final call in calls) {
      expect(jsonDecode(call.arguments['keyAndValue'] as String), isEmpty);
    }
    expect(calls.map((call) => call.arguments).toString(),
        contains('[TradePassword]'));
    expect(calls.map((call) => call.arguments).toString(),
        isNot(contains('secret-')));
  });
}
