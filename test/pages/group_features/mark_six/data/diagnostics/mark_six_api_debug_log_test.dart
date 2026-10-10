import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/diagnostics/group_feature_api_diagnostics.dart';
import 'package:openim/pages/group_features/mark_six/data/diagnostics/mark_six_api_debug_log.dart';

void main() {
  test('logs actual request and binding response without credentials or rows',
      () {
    final output = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => output.add(message ?? '');
    addTearDown(() => debugPrint = originalPrint);
    final request = RequestOptions(
      path: 'https://user:private-password@example.com/me/robot/groups/g',
      headers: {
        'Authorization': 'Bearer private-token',
        'operationID': 'operation-test'
      },
      queryParameters: {'token': 'private-query-token'},
      data: {'password': 'private-body-password'},
    );
    final data = {
      'code': 0,
      'message': 'private-token',
      'data': {
        'groupId': 'g',
        'bound': true,
        'enabled': false,
        'token': 'private-response-token',
        'records': ['private-business-row'],
      },
    };
    final logger = MarkSixApiDebugLog();
    logger.onRequest(request);
    logger.onResponse(
        Response(requestOptions: request, statusCode: 200, data: data));
    logger.onError(DioException(
        requestOptions: request,
        type: DioExceptionType.connectionTimeout,
        message: 'private-token'));
    final log = output.join('\n');
    expect(log, contains('[六合彩API][请求]'));
    expect(log, contains('https://example.com/me/robot/groups/g'));
    expect(log, contains('operation-test'));
    expect(log, contains('"hasBearerToken":true'));
    expect(log, contains('"bound":true'));
    expect(log, contains('"enabled":false'));
    expect(log, contains('connectionTimeout'));
    expect(log, isNot(contains('private-')));
    expect(request.headers['Authorization'], 'Bearer private-token');
    expect(data['message'], 'private-token');
  });

  test('does not report token-only or empty authorization as Bearer auth', () {
    final output = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => output.add(message ?? '');
    addTearDown(() => debugPrint = originalPrint);
    for (final headers in [
      {'token': 'private-token'},
      {'Authorization': 'Bearer '},
      {'Authorization': 'Basic private-token'},
      <String, String>{},
    ]) {
      MarkSixApiDebugLog()
          .onRequest(RequestOptions(path: '/g', headers: headers));
      expect(output.last, contains('"hasBearerToken":false'));
      expect(output.last, isNot(contains('private-')));
    }
  });

  test(
      'trace creates a request-local observer and leaves other scopes unchanged',
      () {
    expect(scopedGroupFeatureDiagnostics(), isNull);
    MarkSixApiDebugLog.trace(() {
      final first = scopedGroupFeatureDiagnostics();
      final second = scopedGroupFeatureDiagnostics();
      expect(first, isA<MarkSixApiDebugLog>());
      expect(second, isA<MarkSixApiDebugLog>());
      expect(identical(first, second), isFalse);
    });
    expect(scopedGroupFeatureDiagnostics(), isNull);
  });
}
