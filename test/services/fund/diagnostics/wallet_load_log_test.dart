import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/fund/diagnostics/wallet_load_log.dart';

void main() {
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

  test('writes are excluded and a failing console never breaks callers', () {
    expect(
        WalletLoadLog.request(
            method: 'PUT',
            url: 'https://chat.test',
            path: '/chat/fund/pay-password',
            operationID: 'write',
            hasToken: true),
        isNull);
    expect(lines, isEmpty);
    debugPrint =
        (String? message, {int? wrapWidth}) => throw StateError('console');
    final trace = WalletLoadLog.start('entry')!;
    expect(() => trace.error(StateError('private data')), returnsNormally);
    expect(() => trace.finish('end'), returnsNormally);
  });
}
