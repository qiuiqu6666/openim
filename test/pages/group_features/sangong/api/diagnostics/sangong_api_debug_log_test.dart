import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/api/diagnostics/sangong_api_debug_log.dart';

const _token = 'actual-chat-token';
const _id = 'operation-sangong-1';

RequestOptions _request({dynamic body}) => RequestOptions(
      baseUrl: 'http://129.226.192.93:10008/sangong/api/v1',
      path: '/me/transfers',
      method: 'POST',
      queryParameters: {'direction': 'out', 'note': '团队 划转', 'limit': 100},
      headers: {
        'operationID': _id,
        'Authorization': 'Bearer $_token',
        'X-Tenant-Id': '@z8hFfDvVQP0x',
        'Content-Type': 'application/json',
      },
      data: body,
    );

String _joined(List<String> logs) => logs.join('\n');

List<String> _parts(List<String> logs, String stage) => logs
    .where((line) => line.startsWith('[三公API][$_id][$stage]'))
    .map((line) => line.replaceFirst(
        RegExp(r'^\[三公API\]\[[^\]]*\]\[[^\]]*\]\[\d+/\d+\] '), ''))
    .toList();

Map<String, dynamic> _payload(List<String> logs, String stage) =>
    jsonDecode(_parts(logs, stage).join()) as Map<String, dynamic>;

void main() {
  late List<String> logs;
  late DebugPrintCallback previousPrint;
  setUp(() {
    logs = [];
    previousPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  tearDown(() => debugPrint = previousPrint);

  test('factory only supplies diagnostics in debug mode', () {
    expect(SangongApiDebugLog.create(),
        kDebugMode ? isA<SangongApiDebugLog>() : isNull);
  });

  test('request logs actual method, full query, tenant and masked credentials',
      () {
    final body = {'toImUserId': 'child', 'amount': 25, 'note': '团队划转'};
    final request = _request(body: body);
    final originalHeaders = Map<String, dynamic>.from(request.headers);
    final originalBody = jsonEncode(body);
    SangongApiDebugLog().onRequest(request);

    final payload = _payload(logs, '请求');
    expect(payload['method'], 'POST');
    expect(payload['url'], request.uri.toString());
    expect((payload['url'] as String), contains('direction=out'));
    expect((payload['url'] as String), contains('limit=100'));
    expect((payload['headers'] as Map)['Authorization'], '***');
    expect((payload['headers'] as Map)['X-Tenant-Id'], '@z8hFfDvVQP0x');
    expect(payload['body'], body);
    expect(_joined(logs), isNot(contains(_token)));
    expect(request.headers, originalHeaders);
    expect(request.data, same(body));
    expect(jsonEncode(body), originalBody);
  });

  test('response includes actual status and the complete original envelope',
      () {
    final request = _request();
    final body = {
      'errCode': 6007,
      'errMsg': '业务处理失败',
      'data': {
        'items': [
          {'id': 'first', 'amount': 12},
          {'id': 'last', 'amount': 34}
        ],
        'pagination': {'total': 2, 'page': 1},
      },
      'serverTrace': 'trace-visible',
    };
    final logger = SangongApiDebugLog()..onRequest(request);
    logger.onResponse(Response<dynamic>(
        requestOptions: request, statusCode: 500, data: body));

    final payload = _payload(logs, '响应');
    expect(payload['status'], 500);
    expect(payload['elapsedMs'], isA<int>());
    expect(payload['data'], body);
    expect(_joined(logs), contains('serverTrace'));
    expect(_joined(logs), contains('trace-visible'));
  });

  test('URL query credentials are masked without changing request or response',
      () {
    final request = _request()
      ..queryParameters.addAll({'token': 'query-secret', 'page': 2});
    const imageUrl = 'https://storage.example/object/image.png'
        '?X-Amz-Signature=storage-secret&height=960&width=960';
    final response = Response<dynamic>(
        requestOptions: request, statusCode: 200, data: {'imageUrl': imageUrl});
    final logger = SangongApiDebugLog()..onRequest(request);
    logger.onResponse(response);

    final output = _joined(logs);
    expect(output, isNot(contains('query-secret')));
    expect(output, isNot(contains('storage-secret')));
    expect(output, contains('page=2'));
    expect(output, contains('height=960'));
    expect(output, contains('width=960'));
    expect(request.queryParameters['token'], 'query-secret');
    expect((response.data as Map)['imageUrl'], imageUrl);
  });

  test('non-JSON response remains readable and removes known header tokens',
      () {
    final request = _request();
    final logger = SangongApiDebugLog()..onRequest(request);
    const raw = '<html>upstream failed for $_token; please retry</html>';
    final response =
        Response<dynamic>(requestOptions: request, statusCode: 502, data: raw);
    logger.onResponse(response);

    final payload = _payload(logs, '响应');
    expect(payload['status'], 502);
    expect(
        payload['data'], '<html>upstream failed for ***; please retry</html>');
    expect(_joined(logs), isNot(contains(_token)));
    expect(response.data, raw);
  });

  test('body and query credentials echoed as text stay masked', () {
    const password = 'setup-password-with spaces';
    const queryToken = 'query-token-secret';
    final body = {
      'credentials': {'password': password},
      'note': 'visible-business-note',
    };
    final request = _request(body: body)
      ..queryParameters['chatToken'] = queryToken;
    final originalBody = jsonEncode(body);
    final logger = SangongApiDebugLog()..onRequest(request);
    final response = Response<dynamic>(
        requestOptions: request,
        statusCode: 403,
        data: {'message': 'Rejected $password and $queryToken'});
    logger.onResponse(response);
    logger.onError(
        StateError('Failed ${Uri.encodeComponent(password)} and $queryToken'));

    final output = _joined(logs);
    expect(output, isNot(contains(password)));
    expect(output, isNot(contains(Uri.encodeComponent(password))));
    expect(output, isNot(contains(queryToken)));
    expect(output, contains('visible-business-note'));
    expect(_payload(logs, '响应')['data'], {'message': 'Rejected *** and ***'});
    expect(jsonEncode(body), originalBody);
    expect(request.queryParameters['chatToken'], queryToken);
    expect((response.data as Map)['message'],
        'Rejected $password and $queryToken');
  });

  test('JSON response text masks unknown nested secrets and preserves the text',
      () {
    final request = _request();
    const raw = '{"errCode":403,"message":"未授权",'
        '"details":{"imToken":"unseen-im-token","password":"unseen-password",'
        '"tenantId":"tenant-visible","attempt":3}}';
    final response =
        Response<dynamic>(requestOptions: request, statusCode: 403, data: raw);
    final logger = SangongApiDebugLog()..onRequest(request);
    logger.onResponse(response);

    expect(_payload(logs, '响应')['data'], {
      'errCode': 403,
      'message': '未授权',
      'details': {
        'imToken': '***',
        'password': '***',
        'tenantId': 'tenant-visible',
        'attempt': 3,
      },
    });
    expect(_joined(logs), isNot(contains('unseen-im-token')));
    expect(_joined(logs), isNot(contains('unseen-password')));
    expect(response.data, raw);
  });

  test(
      'nested JSON secrets are masked without changing business fields or data',
      () {
    final data = {
      'errCode': 0,
      'data': {
        'chatToken': 'private-chat',
        'im_token': 'private-im',
        'refreshToken': 'private-refresh',
        'password': 'private-password',
        'secret': 'private-secret',
        'cookie': 'private-cookie',
        'players': [
          {
            'publicAccountId': 'owner',
            'amount': 75,
            'Authorization': 'private'
          },
          {'publicAccountId': 'child', 'amount': 12, 'token': 'private-token'},
        ],
        'round': {'id': 9, 'status': 'betting'},
      },
    };
    final original = jsonEncode(data);
    final request = _request(body: data)
      ..headers['TOKEN'] = 'legacy-chat-token';
    final originalHeaders = jsonEncode(request.headers);
    final logger = SangongApiDebugLog()..onRequest(request);
    final response =
        Response<dynamic>(requestOptions: request, statusCode: 200, data: data);
    logger.onResponse(response);

    for (final stage in ['请求', '响应']) {
      final payload = _payload(logs, stage);
      final envelope = payload[stage == '请求' ? 'body' : 'data'] as Map;
      final sanitized = envelope['data'] as Map;
      for (final key in [
        'chatToken',
        'im_token',
        'refreshToken',
        'password',
        'secret',
        'cookie'
      ]) {
        expect(sanitized[key], '***');
      }
      expect(sanitized['round'], {'id': 9, 'status': 'betting'});
      expect(sanitized['players'], [
        {'publicAccountId': 'owner', 'amount': 75, 'Authorization': '***'},
        {'publicAccountId': 'child', 'amount': 12, 'token': '***'},
      ]);
    }
    expect(_joined(logs), isNot(contains('private-')));
    expect(_joined(logs), isNot(contains('legacy-chat-token')));
    expect(response.data, same(data));
    expect(request.data, same(data));
    expect(jsonEncode(data), original);
    expect(jsonEncode(request.headers), originalHeaders);
  });

  test('long Unicode body is split completely and keeps its last character',
      () {
    final request = _request();
    final raw = '${List.filled(2600, '汉😀').join()}末尾-END';
    final logger = SangongApiDebugLog()..onRequest(request);
    logger.onResponse(
        Response<dynamic>(requestOptions: request, statusCode: 200, data: raw));

    final parts = _parts(logs, '响应');
    expect(parts.length, greaterThan(1));
    expect(parts.every((part) => part.runes.length <= 800), isTrue);
    expect(_payload(logs, '响应')['data'], raw);
    expect(parts.last, contains('末尾-END'));
    expect(logs.where((line) => line.startsWith('[三公API][$_id][响应]')).last,
        contains('[${parts.length}/${parts.length}]'));
  });

  test('SSE fragmented data logs one complete event including non-state types',
      () {
    final logger = SangongApiDebugLog()..onRequest(_request());
    const first = 'event: heart';
    const second =
        'beat\ndata: {"online":true,\ndata: "chatToken":"private-sse"}';
    logger.onStreamData(first);
    logger.onStreamData(second);
    expect(_parts(logs, 'SSE事件'), isEmpty);
    logger.onStreamData('\n\n');

    final event = _payload(logs, 'SSE事件');
    expect(event['event'], 'heartbeat');
    expect(event['data'], {'online': true, 'chatToken': '***'});
    expect(_joined(logs), isNot(contains('private-sse')));
  });

  test('default SSE message preserves plain data and masks echoed credentials',
      () {
    final logger = SangongApiDebugLog()..onRequest(_request());
    logger.onStreamData('data: 调试连接 $_token\r\n\r\n');
    final event = _payload(logs, 'SSE事件');
    expect(event['event'], 'message');
    expect(event['data'], '调试连接 ***');
    expect(_joined(logs), isNot(contains(_token)));
  });

  test('ResponseBody is marked as SSE without listening to its stream',
      () async {
    var listened = false;
    final stream =
        StreamController<Uint8List>.broadcast(onListen: () => listened = true);
    addTearDown(stream.close);
    final body = ResponseBody(stream.stream, 200, headers: {
      Headers.contentTypeHeader: ['text/event-stream'],
    });
    final originalStream = body.stream;
    final request = _request();
    final logger = SangongApiDebugLog()..onRequest(request);
    logger.onResponse(Response<dynamic>(
        requestOptions: request, statusCode: 200, data: body));

    expect(listened, isFalse);
    expect(_payload(logs, '响应')['data'], '<SSE流，未读取>');
    expect(body.stream, same(originalStream));
  });

  test('Dio error keeps its real status, response body and safe error detail',
      () {
    final request = _request();
    final data = {'errCode': 4001, 'message': '服务拒绝 $_token', 'reason': '余额不足'};
    final response =
        Response<dynamic>(requestOptions: request, statusCode: 403, data: data);
    final error = DioException(
      requestOptions: request,
      response: response,
      type: DioExceptionType.badResponse,
      message: '服务错误 $_token',
      error: StateError('inner failure $_token'),
    );
    final logger = SangongApiDebugLog()..onRequest(request);
    logger.onError(error);

    final payload = _payload(logs, '异常');
    expect(payload['type'], 'badResponse');
    expect(payload['status'], 403);
    expect(payload['url'], request.uri.toString());
    expect((payload['data'] as Map)['reason'], '余额不足');
    expect((payload['data'] as Map)['message'], '服务拒绝 ***');
    expect(_joined(logs), contains('inner failure ***'));
    expect(_joined(logs), isNot(contains(_token)));
    expect(response.data, same(data));
    expect(data['message'], '服务拒绝 $_token');
    expect(error.message, '服务错误 $_token');
  });

  test('SSE errors are readable and stream completion is logged once', () {
    final logger = SangongApiDebugLog()..onRequest(_request());
    logger.onError(StateError('实时连接中断 $_token'));
    logger.onStreamClosed();
    logger.onStreamClosed();
    logger.onStreamData('data: ignored after close\n\n');

    expect(_payload(logs, '异常')['type'], 'StateError');
    expect(_joined(logs), contains('实时连接中断 ***'));
    expect(_parts(logs, '结束'), hasLength(1));
    expect(_payload(logs, '结束')['elapsedMs'], isA<int>());
    expect(_parts(logs, 'SSE事件'), isEmpty);
    expect(_joined(logs), isNot(contains(_token)));
  });
}
