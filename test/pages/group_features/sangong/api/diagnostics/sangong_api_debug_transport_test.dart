import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/diagnostics/group_feature_api_diagnostics.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/api/diagnostics/sangong_api_debug_log.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';

import '../../sangong_test_support.dart';

const _chatToken = 'chat-token-debug-secret';
const _tenant = '@z8hFfDvVQP0x';
const _businessBase = 'http://129.226.192.93:10008/sangong/api/v1';

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (respond != null) return await respond!(options);
    return _envelope({'round': null, 'status': 'idle'});
  }

  @override
  void close({bool force = false}) {}
}

class _ChatApi extends GroupFeatureApi {
  _ChatApi(_Transport transport)
      : super(
            client: Dio()..httpClientAdapter = transport,
            baseUrl: 'https://chat.example',
            tokenProvider: () => _chatToken,
            userProvider: () => 'owner');
}

class _ThrowingDiagnostics implements GroupFeatureApiDiagnostics {
  int requests = 0, responses = 0, chunks = 0, closures = 0;

  @override
  void onRequest(RequestOptions request) {
    requests++;
    throw StateError('request observer failed');
  }

  @override
  void onResponse(Response<dynamic> response) {
    responses++;
    throw StateError('response observer failed');
  }

  @override
  void onError(Object error) => throw StateError('error observer failed');

  @override
  void onStreamData(String chunk) {
    chunks++;
    throw StateError('stream observer failed');
  }

  @override
  void onStreamClosed() {
    closures++;
    throw StateError('closure observer failed');
  }
}

ResponseBody _rawJson(dynamic raw, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(raw), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

ResponseBody _envelope(dynamic data, {int status = 200}) =>
    _rawJson({'errCode': 0, 'data': data}, status: status);

GroupFeatureContext _context(
        GroupFeatureApi api, FixtureAccountPrivilege privilege,
        {bool canConfigure = true, bool canManage = true}) =>
    GroupFeatureContext(
        groupID: 'group-sangong',
        groupName: '三公交流群',
        currentUserID: 'owner',
        api: api,
        accountPrivilege: privilege,
        features: const GroupFeatures(
            valid: true,
            revision: 1,
            sangong: GroupGameFeature(
                enabled: true,
                manageEntry: true,
                agentEntry: true,
                rebateHistoryEntry: true)),
        capabilities: GroupFeatureCapabilities(
            version: 1,
            sangong: GroupGameCapabilities(
                canConfigure: canConfigure,
                canManage: canManage,
                canOpenAgent: true,
                canViewRebateHistory: true,
                tenantID: 'tenant-authorized')),
        sessionCurrent: () => true,
        onFeaturesChanged: (_) {});

void _expectSangongCredentials(RequestOptions request,
    {String tenant = _tenant}) {
  expect(request.headers['Authorization'], 'Bearer $_chatToken');
  expect(request.headers.containsKey('token'), isFalse);
  expect(request.headers['X-Tenant-Id'], tenant);
  expect(request.headers['operationID'], isNotEmpty);
}

void _expectCorrelatedLog(List<String> logs, RequestOptions request) {
  final operationID = request.headers['operationID'].toString();
  final correlated = logs.where((line) => line.contains(operationID)).toList();
  expect(correlated.any((line) => line.contains('请求')), isTrue);
  expect(correlated.any((line) => line.contains('响应')), isTrue);
  expect(logs.join('\n'), isNot(contains(_chatToken)));
  expect(logs.join('\n'), isNot(contains('https://sangong.invalid')));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport transport;
  late _ChatApi api;
  late FixtureAccountPrivilege privilege;
  late List<String> logs;
  late DebugPrintCallback previousDebugPrint;

  setUp(() {
    transport = _Transport();
    api = _ChatApi(transport);
    privilege = FixtureAccountPrivilege();
    logs = <String>[];
    previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });

  tearDown(() {
    debugPrint = previousDebugPrint;
    privilege.dispose();
  });

  SangongRuntime runtime() {
    final value = SangongRuntime(_context(api, privilege),
        baseUrl: _businessBase,
        configuredTenantId: _tenant,
        pathPrefix: '/legacy/proxy');
    addTearDown(value.dispose);
    return value;
  }

  test(
      'automatic HTTP diagnostics keep real URL, query, status and raw envelope',
      () async {
    const raw = {
      'errCode': 0,
      'data': {
        'reportSummary': 'complete-overview',
        'items': [
          {'amount': 17},
          {'marker': 'response-tail-sentinel'}
        ]
      },
      'meta': {'total': 47}
    };
    transport.respond = (_) => _rawJson(raw, status: 206);
    final scope = runtime();

    final response = await scope.http.requests.get(
        '/api/v1/me/reports/overview',
        queryParameters: {'range': 'all time', 'limit': 2});

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.path, '/sangong/api/v1/me/reports/overview');
    expect(request.queryParameters, {'range': 'all time', 'limit': 2});
    expect(response.data, raw);
    _expectSangongCredentials(request, tenant: 'tenant-authorized');
    _expectCorrelatedLog(logs, request);
    final output = logs.join('\n');
    expect(output, contains('[三公API]'));
    expect(output, contains(request.uri.toString()));
    expect(output, contains('206'));
    for (final key in ['errCode', 'data', 'meta', 'total', 'range', 'limit']) {
      expect(output, contains(key));
    }
    expect(output, contains('response-tail-sentinel'));
    expect(output, contains('complete-overview'));
  });

  test('non-200 raw error bodies are logged before existing exception mapping',
      () async {
    final scope = runtime();
    for (final status in [403, 500]) {
      logs.clear();
      transport.respond = (_) => _rawJson({
            'message': 'server-$status-reply',
            'error': {
              'marker': 'http-$status-detail',
              'nested': ['raw-error-tail']
            }
          }, status: status);

      await expectLater(
          scope.http.requests.get('/api/v1/admin/session'),
          throwsA(isA<DioException>().having(
              (error) => error.error,
              'existing business exception',
              isA<GroupFeatureException>().having((error) => error.code, 'code',
                  status == 403 ? 'FORBIDDEN' : 'HTTP_500'))));

      final request = transport.requests.last;
      _expectSangongCredentials(request, tenant: 'tenant-authorized');
      _expectCorrelatedLog(logs, request);
      final output = logs.join('\n');
      expect(output, contains('$status'));
      expect(output, contains('server-$status-reply'));
      expect(output, contains('http-$status-detail'));
      expect(output, contains('raw-error-tail'));
    }
  });

  test('network failures and cancellation log without leaking the Chat token',
      () async {
    transport.respond = (request) => throw DioException(
        requestOptions: request,
        type: DioExceptionType.connectionError,
        error: 'connection failed token=$_chatToken');

    await expectLater(
        api.requestData('/admin/session',
            baseUrlOverride: _businessBase,
            headers: {'X-Tenant-Id': _tenant},
            useBearerAuth: true,
            diagnostics: SangongApiDebugLog.create()),
        throwsA(isA<GroupFeatureException>()
            .having((error) => error.code, 'code', 'NETWORK_ERROR')));

    final failedRequest = transport.requests.single;
    _expectSangongCredentials(failedRequest);
    expect(logs.join('\n'), contains('异常'));
    expect(logs.join('\n'), contains('connection failed'));
    expect(logs.join('\n'), contains(failedRequest.headers['operationID']));
    expect(logs.join('\n'), isNot(contains(_chatToken)));

    logs.clear();
    final opened = Completer<void>();
    final reply = Completer<ResponseBody>();
    transport.respond = (_) {
      opened.complete();
      return reply.future;
    };
    final cancel = CancelToken();
    final request = api.requestData('/admin/session',
        baseUrlOverride: _businessBase,
        headers: {'X-Tenant-Id': _tenant},
        useBearerAuth: true,
        cancelToken: cancel,
        diagnostics: SangongApiDebugLog.create());
    final rejected = expectLater(
        request,
        throwsA(isA<GroupFeatureException>()
            .having((error) => error.code, 'code', 'CANCELLED')));
    await opened.future;
    cancel.cancel('caller cancelled token=$_chatToken');
    await rejected;
    reply.complete(_envelope({'status': 'idle'}));

    _expectSangongCredentials(transport.requests.last);
    expect(logs.join('\n'), contains('异常'));
    expect(logs.join('\n'),
        contains(transport.requests.last.headers['operationID']));
    expect(logs.join('\n'), isNot(contains(_chatToken)));
  });

  test('shared Chat requests keep their credentials and produce no Sangong log',
      () async {
    await api.get('/chat/groups/group-sangong/feature-capabilities');

    final request = transport.requests.single;
    expect(request.uri.toString(),
        'https://chat.example/chat/groups/group-sangong/feature-capabilities');
    expect(request.headers['token'], _chatToken);
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.headers.containsKey('X-Tenant-Id'), isFalse);
    expect(logs.where((line) => line.contains('[三公API]')), isEmpty);
  });

  test('Sangong trace logs shared capabilities only inside its async scope',
      () async {
    const path = '/chat/groups/group/feature-capabilities';
    const capability = {
      'groupID': 'group',
      'capabilityVersion': 7,
      'sangong': {'canConfigure': false, 'canManage': false},
      'marker': 'shared-capabilities-response-tail'
    };
    transport.respond = (_) => _envelope(capability);

    final result = await SangongApiDebugLog.trace(() async {
      await Future<void>.delayed(Duration.zero);
      return api.get(path);
    });

    final request = transport.requests.single;
    expect(result, capability);
    expect(request.method, 'GET');
    expect(request.uri.toString(), 'https://chat.example$path');
    expect(request.headers['token'], _chatToken);
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.headers.containsKey('X-Tenant-Id'), isFalse);
    _expectCorrelatedLog(logs, request);
    final output = logs.join('\n');
    expect(output, contains(request.uri.toString()));
    expect(output, contains('capabilityVersion'));
    expect(output, contains('shared-capabilities-response-tail'));
    expect(output, contains('errCode'));

    logs.clear();
    expect(await api.get(path), capability);
    expect(transport.requests, hasLength(2));
    expect(transport.requests.last.headers['token'], _chatToken);
    expect(logs.where((line) => line.contains('[三公API]')), isEmpty);
  });

  test('throwing scoped factories cannot change HTTP or SSE results', () async {
    const frame = 'event: audit\ndata: scoped-factory-still-usable\n\n';
    var factoryCalls = 0;
    GroupFeatureApiDiagnostics? factory() {
      factoryCalls++;
      throw StateError('scoped diagnostics factory failed');
    }

    transport.respond = (request) => request.uri.path.endsWith('/events/stream')
        ? ResponseBody(
            Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(frame))),
            200,
            headers: {
                Headers.contentTypeHeader: ['text/event-stream']
              })
        : _envelope({'marker': 'scoped-factory-http-still-usable'});

    final result = await withGroupFeatureDiagnostics(() async {
      await Future<void>.delayed(Duration.zero);
      return api.get('/chat/groups/group/feature-capabilities');
    }, factory);
    final chunks = await withGroupFeatureDiagnostics(
        () => api.eventStream('/shared/events/stream').toList(), factory);

    expect(result, {'marker': 'scoped-factory-http-still-usable'});
    expect(chunks.join(), frame);
    expect(factoryCalls, 2);
    expect(transport.requests, hasLength(2));
    for (final request in transport.requests) {
      expect(request.headers['token'], _chatToken);
      expect(request.headers.containsKey('Authorization'), isFalse);
    }
    expect(logs.where((line) => line.contains('[三公API]')), isEmpty);
  });

  test('explicit diagnostics take precedence over the HTTP and SSE scope',
      () async {
    const frame = 'event: audit\ndata: explicit-observer-still-usable\n\n';
    final explicit = _ThrowingDiagnostics();
    var factoryCalls = 0;
    GroupFeatureApiDiagnostics? factory() {
      factoryCalls++;
      return SangongApiDebugLog.create();
    }

    transport.respond = (request) => request.uri.path.endsWith('/events/stream')
        ? ResponseBody(
            Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(frame))),
            200,
            headers: {
                Headers.contentTypeHeader: ['text/event-stream']
              })
        : _envelope({'marker': 'explicit-observer-http-still-usable'});

    final result = await withGroupFeatureDiagnostics(
        () => api.requestData('/chat/groups/group/feature-capabilities',
            diagnostics: explicit),
        factory);
    final chunks = await withGroupFeatureDiagnostics(
        () => api
            .eventStream('/shared/events/stream', diagnostics: explicit)
            .toList(),
        factory);

    expect(result, {'marker': 'explicit-observer-http-still-usable'});
    expect(chunks.join(), frame);
    expect(explicit.requests, 2);
    expect(explicit.responses, 2);
    expect(explicit.chunks, greaterThan(0));
    expect(explicit.closures, 1);
    expect(factoryCalls, 0);
    expect(logs.where((line) => line.contains('[三公API]')), isEmpty);
  });

  test('local missing group permissions log the denial without a business call',
      () async {
    final scope = SangongRuntime(
        _context(api, privilege, canConfigure: false, canManage: false),
        baseUrl: _businessBase,
        configuredTenantId: _tenant);
    addTearDown(scope.dispose);

    expect(scope.isPrivileged, isTrue);
    await expectLater(
        scope.ensureManageBinding(),
        throwsA(isA<StateError>()
            .having((error) => error.message, 'reason', '没有当前群的三公配置或运营权限')));

    expect(transport.requests, isEmpty);
    final output = logs.join('\n');
    expect(output, contains('[三公API]'));
    expect(output, contains('权限检查'));
    expect(output, contains('没有当前群的三公配置或运营权限'));
    expect(output, contains('group-sangong'));
    expect(output, contains('canConfigure'));
    expect(output, contains('canManage'));
    expect(output, isNot(contains(_chatToken)));
  });

  test('SSE diagnostics log complete events across chunks and close once',
      () async {
    final body = StreamController<Uint8List>();
    addTearDown(body.close);
    final opened = Completer<void>();
    transport.respond = (_) {
      opened.complete();
      return ResponseBody(body.stream, 200, headers: {
        Headers.contentTypeHeader: ['text/event-stream']
      });
    };
    final received = api
        .eventStream('/admin/events/stream',
            baseUrlOverride: _businessBase,
            headers: {'X-Tenant-Id': _tenant},
            useBearerAuth: true,
            diagnostics: SangongApiDebugLog.create())
        .toList();
    await opened.future;
    const frame =
        'event: audit\ndata: {"marker":"cross-chunk","detail":"完整返回"}\n\n';
    final bytes = utf8.encode(frame);
    final firstSplit =
        utf8.encode('event: audit\ndata: {"marker":"cross-').length;
    final secondSplit = utf8
            .encode('event: audit\ndata: {"marker":"cross-chunk","detail":"')
            .length +
        1;
    body.add(Uint8List.fromList(bytes.sublist(0, firstSplit)));
    body.add(Uint8List.fromList(bytes.sublist(firstSplit, secondSplit)));
    body.add(Uint8List.fromList(bytes.sublist(secondSplit)));
    await body.close();
    expect((await received).join(), frame);

    final request = transport.requests.single;
    expect(request.method, 'GET');
    expect(request.uri.toString(), '$_businessBase/admin/events/stream');
    expect(request.headers['Accept'], 'text/event-stream');
    _expectSangongCredentials(request);
    _expectCorrelatedLog(logs, request);
    final eventLogs = logs.where((line) => line.contains('SSE事件')).toList();
    expect(eventLogs, hasLength(1));
    expect(eventLogs.single, contains('audit'));
    expect(eventLogs.single, contains('cross-chunk'));
    expect(eventLogs.single, contains('完整返回'));
    expect(logs.where((line) => line.contains('结束')), hasLength(1));
    expect(logs.join('\n'), contains('200'));
  });

  test('rejected SSE logs its finite raw body with secrets masked', () async {
    const password = 'diagnostic-password-secret';
    transport.respond = (_) => _rawJson({
          'message': 'SSE server rejected the request',
          'token': _chatToken,
          'password': password,
          'data': {'marker': 'sse-server-error-tail'}
        }, status: 503);

    await expectLater(
        api
            .eventStream('/admin/events/stream',
                baseUrlOverride: _businessBase,
                headers: {'X-Tenant-Id': _tenant},
                useBearerAuth: true,
                diagnostics: SangongApiDebugLog.create())
            .toList(),
        throwsA(isA<GroupFeatureException>().having(
            (error) => error.code, 'code', 'EVENT_STREAM_UNAVAILABLE')));

    final request = transport.requests.single;
    _expectSangongCredentials(request);
    _expectCorrelatedLog(logs, request);
    final output = logs.join('\n');
    expect(output, contains('503'));
    expect(output, contains('SSE server rejected the request'));
    expect(output, contains('sse-server-error-tail'));
    expect(output, isNot(contains(password)));
    expect(output, isNot(contains(_chatToken)));
    expect(logs.where((line) => line.contains('结束')), hasLength(1));
  });

  test('throwing observers cannot change successful HTTP or SSE results',
      () async {
    const frame = 'event: audit\ndata: {"marker":"stream-still-usable"}\n\n';
    final observer = _ThrowingDiagnostics();
    transport.respond = (request) => request.uri.path.endsWith('/events/stream')
        ? ResponseBody(
            Stream<Uint8List>.value(Uint8List.fromList(utf8.encode(frame))),
            200,
            headers: {
                Headers.contentTypeHeader: ['text/event-stream']
              })
        : _envelope({'marker': 'http-still-usable'});

    final result = await api.requestData('/admin/session',
        baseUrlOverride: _businessBase,
        headers: {'X-Tenant-Id': _tenant},
        useBearerAuth: true,
        diagnostics: observer);
    final chunks = await api
        .eventStream('/admin/events/stream',
            baseUrlOverride: _businessBase,
            headers: {'X-Tenant-Id': _tenant},
            useBearerAuth: true,
            diagnostics: observer)
        .toList();

    expect(result, {'marker': 'http-still-usable'});
    expect(chunks.join(), frame);
    expect(observer.requests, 2);
    expect(observer.responses, 2);
    expect(observer.chunks, greaterThan(0));
    expect(observer.closures, 1);
    for (final request in transport.requests) {
      _expectSangongCredentials(request);
    }
  });

  test('a stalled SSE error body cannot block connection failure', () async {
    final body = StreamController<Uint8List>();
    addTearDown(body.close);
    transport.respond = (_) => ResponseBody(body.stream, 503, headers: {
          Headers.contentTypeHeader: ['application/json']
        });

    await expectLater(
        api
            .eventStream('/admin/events/stream',
                baseUrlOverride: _businessBase,
                headers: {'X-Tenant-Id': _tenant},
                useBearerAuth: true,
                diagnostics: SangongApiDebugLog.create())
            .toList()
            .timeout(const Duration(seconds: 5)),
        throwsA(isA<GroupFeatureException>().having(
            (error) => error.code, 'code', 'EVENT_STREAM_UNAVAILABLE')));

    expect(logs.join('\n'), contains('错误响应读取超时'));
    expect(logs.where((line) => line.contains('结束')), hasLength(1));
  });

  test('realtime automatically opts its stream and snapshot into diagnostics',
      () async {
    final body = StreamController<Uint8List>();
    addTearDown(body.close);
    final opened = Completer<void>();
    transport.respond = (request) {
      if (request.uri.path.endsWith('/events/stream')) {
        opened.complete();
        return ResponseBody(body.stream, 200, headers: {
          Headers.contentTypeHeader: ['text/event-stream']
        });
      }
      return _envelope(sangongState(1));
    };
    final scope = runtime();
    scope.realtime.acquire();
    await opened.future;
    await scope.realtime.refreshSnapshot();
    final accepted = Completer<void>();
    void changed() {
      if (scope.realtime.latestState?.version == 2 && !accepted.isCompleted) {
        accepted.complete();
      }
    }

    scope.realtime.addListener(changed);
    body.add(Uint8List.fromList(
        utf8.encode('event: state\ndata: ${jsonEncode(sangongState(2))}\n\n')));
    await accepted.future;
    scope.realtime.removeListener(changed);
    scope.realtime.release();

    final streamRequest = transport.requests
        .singleWhere((request) => request.uri.path.endsWith('/events/stream'));
    final snapshotRequest = transport.requests.singleWhere(
        (request) => request.uri.path.endsWith('/events/snapshot'));
    for (final request in [streamRequest, snapshotRequest]) {
      _expectSangongCredentials(request, tenant: 'tenant-authorized');
      _expectCorrelatedLog(logs, request);
      expect(logs.join('\n'), contains(request.uri.toString()));
    }
    expect(logs.any((line) => line.contains('SSE事件')), isTrue);
    expect(scope.realtime.latestState?.version, 2);
    expect(scope.realtime.ownerCount, 0);
  });
}
