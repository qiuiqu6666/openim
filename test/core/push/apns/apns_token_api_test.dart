import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/core/push/apns/apns_token_api.dart';

Map<String, dynamic> _ack({bool deleting = false}) => {
      'errCode': 0,
      'errMsg': '',
      'data': <String, dynamic>{
        'userID': 'captured-user',
        'platformID': 1,
        if (deleting) 'removed': 0 else 'deviceID': 'captured-device',
      },
    };

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? respond;
  bool closed = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond == null
        ? _json(_ack(deleting: options.path.endsWith('/delete_push_token')))
        : await respond!(options);
  }

  @override
  void close({bool force = false}) => closed = true;
}

ResponseBody _json(dynamic body, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

Matcher _failure(String code, {int? status}) =>
    throwsA(isA<ApnsTokenApiException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.statusCode, 'statusCode', status));

void main() {
  late _Transport transport;
  late Dio source;
  late ApnsTokenApi api;

  Future<void> register({CancelToken? cancellation}) => api.register(
      token: 'native-apns-token',
      bundleId: 'vip.99chat.ios',
      apsEnvironment: 'production',
      cancelToken: cancellation);

  setUp(() {
    transport = _Transport();
    source = Dio()..httpClientAdapter = transport;
    api = ApnsTokenApi(
        baseUrl: 'https://im.example/api/',
        imToken: 'captured-im-token',
        userID: 'captured-user',
        deviceID: 'captured-device',
        client: source);
  });

  tearDown(() {
    api.close();
    source.close();
  });

  test('register uses IM token and the OpenIM native APNs contract', () async {
    await register();
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
        request.uri.toString(), 'https://im.example/api/third/set_push_token');
    expect(request.headers['token'], 'captured-im-token');
    expect(request.headers['operationID'], isNotEmpty);
    expect(request.contentType, Headers.jsonContentType);
    expect(request.data, {
      'platformID': 1,
      'deviceID': 'captured-device',
      'provider': 'apns',
      'token': 'native-apns-token',
      'environment': 'production',
    });
    final names = request.headers.keys.map((key) => key.toLowerCase());
    expect(names, isNot(contains('authorization')));
    expect(names, isNot(contains('x-tenant-id')));
    expect(request.followRedirects, isFalse);
    expect(request.maxRedirects, 0);
    expect(request.connectTimeout, ApnsTokenApi.requestTimeout);
    expect(request.sendTimeout, ApnsTokenApi.requestTimeout);
    expect(request.receiveTimeout, ApnsTokenApi.requestTimeout);
  });

  test('development environment is sent without a bundle or VoIP field',
      () async {
    await api.register(
        token: 'native-apns-token',
        bundleId: '',
        apsEnvironment: 'development');
    expect(transport.requests.single.data, {
      'platformID': 1,
      'deviceID': 'captured-device',
      'provider': 'apns',
      'token': 'native-apns-token',
      'environment': 'development',
    });
  });

  test('borrowed Dio cannot leak defaults, cookies or global interceptors',
      () async {
    var intercepted = false;
    source.options.headers.addAll({
      'token': 'other-im-token',
      'Authorization': 'Bearer other-chat-token',
      'X-Tenant-Id': 'sangong-tenant',
      'Cookie': 'other-account-cookie',
    });
    source.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      intercepted = true;
      handler.next(options);
    }));
    await register();
    expect(intercepted, isFalse);
    final headers = transport.requests.single.headers;
    expect(headers['token'], 'captured-im-token');
    final names = headers.keys.map((key) => key.toLowerCase());
    expect(names, isNot(contains('authorization')));
    expect(names, isNot(contains('x-tenant-id')));
    expect(names, isNot(contains('cookie')));
    expect(source.options.headers['token'], 'other-im-token');
  });

  test('logout posts to IM unbinding with the captured old identity', () async {
    source.options.baseUrl = 'https://next-server.example';
    source.options.headers['token'] = 'next-account-im-token';
    await api.delete();
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.toString(),
        'https://im.example/api/third/delete_push_token');
    expect(request.headers['token'], 'captured-im-token');
    expect(request.data, {'platformID': 1, 'deviceID': 'captured-device'});
  });

  test('operation IDs distinguish registration and unregister requests',
      () async {
    await register();
    await api.delete();
    expect(transport.requests[0].headers['operationID'],
        isNot(transport.requests[1].headers['operationID']));
  });

  test('accepts acknowledged HTTP 201 registration', () async {
    transport.respond = (_) => _json(_ack(), status: 201);
    await register();
  });

  test('supports JSON acknowledgement sent with a text content type', () async {
    transport.respond =
        (_) => ResponseBody.fromString(jsonEncode(_ack()), 200, headers: {
              Headers.contentTypeHeader: ['text/plain']
            });
    await register();
  });

  for (final code in [null, 20101, '0', 0.0, true]) {
    test('register and unbinding require integer errCode zero: $code',
        () async {
      transport.respond = (request) => _json(
          _ack(deleting: request.path.endsWith('/delete_push_token'))
            ..['errCode'] = code);
      await expectLater(register(), _failure('INVALID_RESPONSE', status: 200));
      await expectLater(
          api.delete(), _failure('INVALID_RESPONSE', status: 200));
    });
  }

  for (final id in [null, '', 'other-user', 1]) {
    test('register and unbinding must acknowledge captured user ID: $id',
        () async {
      transport.respond = (request) {
        final body =
            _ack(deleting: request.path.endsWith('/delete_push_token'));
        (body['data'] as Map)['userID'] = id;
        return _json(body);
      };
      await expectLater(register(), _failure('INVALID_RESPONSE', status: 200));
      await expectLater(
          api.delete(), _failure('INVALID_RESPONSE', status: 200));
    });
  }

  for (final platform in [null, 2, '1', 1.0, true]) {
    test('register and unbinding require iOS platform ID: $platform', () async {
      transport.respond = (request) {
        final body =
            _ack(deleting: request.path.endsWith('/delete_push_token'));
        (body['data'] as Map)['platformID'] = platform;
        return _json(body);
      };
      await expectLater(register(), _failure('INVALID_RESPONSE', status: 200));
      await expectLater(
          api.delete(), _failure('INVALID_RESPONSE', status: 200));
    });
  }

  for (final device in [null, '', 'other-device', 1]) {
    test('registration must acknowledge the captured device ID: $device',
        () async {
      final body = _ack();
      (body['data'] as Map)['deviceID'] = device;
      transport.respond = (_) => _json(body);
      await expectLater(register(), _failure('INVALID_RESPONSE', status: 200));
    });
  }

  for (final removed in [0, 1, 3]) {
    test('unbinding accepts a nonnegative integer removed count: $removed',
        () async {
      final body = _ack(deleting: true);
      (body['data'] as Map)['removed'] = removed;
      transport.respond = (_) => _json(body);
      await api.delete();
    });
  }

  for (final removed in [null, -1, '0', 0.0, 1.5, true]) {
    test('unbinding rejects an invalid removed count: $removed', () async {
      final body = _ack(deleting: true);
      (body['data'] as Map)['removed'] = removed;
      transport.respond = (_) => _json(body);
      await expectLater(
          api.delete(), _failure('INVALID_RESPONSE', status: 200));
    });
  }

  test('unbinding rejects a contradictory device ID when returned', () async {
    final body = _ack(deleting: true);
    (body['data'] as Map)['deviceID'] = 'other-device';
    transport.respond = (_) => _json(body);
    await expectLater(api.delete(), _failure('INVALID_RESPONSE', status: 200));
  });

  test('negative business acknowledgement cannot override matching identity',
      () async {
    for (final nested in [false, true]) {
      transport.respond = (request) {
        final body =
            _ack(deleting: request.path.endsWith('/delete_push_token'));
        (nested ? body['data'] as Map : body)['ok'] = false;
        return _json(body);
      };
      await expectLater(register(), _failure('INVALID_RESPONSE', status: 200));
      await expectLater(
          api.delete(), _failure('INVALID_RESPONSE', status: 200));
    }
  });

  for (final body in [
    null,
    [],
    {'ok': true, 'provider': 'APNS'},
    {'errCode': 0},
    {
      'errCode': 0,
      'data': {'ok': true}
    },
    {'errCode': 0, 'data': 'invalid'},
  ]) {
    test(
        'legacy or malformed responses cannot acknowledge either request: $body',
        () async {
      transport.respond = (_) => _json(body);
      await expectLater(register(), _failure('INVALID_RESPONSE', status: 200));
      await expectLater(
          api.delete(), _failure('INVALID_RESPONSE', status: 200));
    });
  }

  test('empty HTTP 204 cannot confirm the OpenIM unregister acknowledgement',
      () async {
    transport.respond = (_) => ResponseBody.fromString('', 204);
    await expectLater(api.delete(), _failure('INVALID_RESPONSE', status: 204));
  });

  test('non-JSON success bodies cannot acknowledge either request', () async {
    transport.respond =
        (_) => ResponseBody.fromString('<html>ok</html>', 200, headers: {
              Headers.contentTypeHeader: ['text/html']
            });
    await expectLater(register(), _failure('INVALID_RESPONSE', status: 200));
    await expectLater(api.delete(), _failure('INVALID_RESPONSE', status: 200));
  });

  for (final status in [301, 307, 401, 403, 500]) {
    test('registration and unbinding require HTTP success: $status', () async {
      transport.respond = (request) => _json(
          _ack(deleting: request.path.endsWith('/delete_push_token')),
          status: status);
      await expectLater(register(), _failure('HTTP_ERROR', status: status));
      await expectLater(api.delete(), _failure('HTTP_ERROR', status: status));
    });
  }

  test('caller cancellation reaches the active transport request', () async {
    final arrived = Completer<void>();
    final body = Completer<ResponseBody>();
    transport.respond = (_) {
      arrived.complete();
      return body.future;
    };
    final cancellation = CancelToken();
    final pending = register(cancellation: cancellation);
    final assertion = expectLater(
        pending,
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'cancelled', true)));
    await arrived.future;
    cancellation.cancel('caller stopped');
    await assertion;
    body.complete(_json(_ack()));
  });

  test('closing cancels an active request without closing borrowed adapter',
      () async {
    final arrived = Completer<void>();
    final body = Completer<ResponseBody>();
    transport.respond = (_) {
      arrived.complete();
      return body.future;
    };
    final pending = register();
    final assertion = expectLater(
        pending,
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'cancelled', true)));
    await arrived.future;
    api.close();
    await assertion;
    expect(transport.closed, isFalse);
    body.complete(_json(_ack()));
    await expectLater(api.delete(), _failure('CANCELLED'));
  });

  test('already cancelled requests never reach the transport', () async {
    final cancellation = CancelToken()..cancel();
    await expectLater(
        register(cancellation: cancellation),
        throwsA(isA<DioException>()
            .having(CancelToken.isCancel, 'cancelled', true)));
    expect(transport.requests, isEmpty);
  });

  test('IM base preserves its path prefix including a final chat segment', () {
    expect(ApnsTokenApi.normalizeBaseUrl(' https://im.example/api/chat/// '),
        'https://im.example/api/chat');
    expect(ApnsTokenApi.normalizeBaseUrl('http://127.0.0.1:10002/'),
        'http://127.0.0.1:10002');
  });

  for (final base in [
    'file:///tmp/chat',
    'https://user:password@im.example',
    'https://im.example?token=private',
    'https://im.example#fragment',
    '/chat',
  ]) {
    test('rejects unsafe service URL without dispatching: $base', () {
      expect(() => ApnsTokenApi.normalizeBaseUrl(base), throwsArgumentError);
      expect(transport.requests, isEmpty);
    });
  }

  test('missing captured IM credentials fail before HTTP dispatch', () async {
    api.close();
    api = ApnsTokenApi(
        baseUrl: 'https://im.example',
        imToken: '',
        userID: 'captured-user',
        deviceID: 'device',
        client: source);
    await expectLater(api.delete(), _failure('AUTH_INVALID'));
    expect(transport.requests, isEmpty);
  });

  test('missing captured user identity fails before HTTP dispatch', () async {
    api.close();
    api = ApnsTokenApi(
        baseUrl: 'https://im.example',
        imToken: 'captured-im-token',
        userID: '',
        deviceID: 'device',
        client: source);
    await expectLater(api.delete(), _failure('AUTH_INVALID'));
    expect(transport.requests, isEmpty);
  });

  test('missing device identity fails before HTTP dispatch', () async {
    api.close();
    api = ApnsTokenApi(
        baseUrl: 'https://im.example',
        imToken: 'captured-im-token',
        userID: 'captured-user',
        deviceID: '',
        client: source);
    await expectLater(api.delete(), _failure('DEVICE_INVALID'));
    expect(transport.requests, isEmpty);
  });

  test('empty native token and unknown APNs environment are not uploaded',
      () async {
    await expectLater(
        api.register(token: '', bundleId: '', apsEnvironment: 'production'),
        _failure('TOKEN_INVALID'));
    await expectLater(
        api.register(token: 'native-token', bundleId: '', apsEnvironment: ''),
        _failure('CONFIG_INVALID'));
    expect(transport.requests, isEmpty);
  });
}
