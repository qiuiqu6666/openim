import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';

import '../sangong_test_support.dart';

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (respond != null) return await respond!(options);
    return _json({'round': null, 'status': 'idle'});
  }

  @override
  void close({bool force = false}) {}
}

class _ChatApi extends GroupFeatureApi {
  _ChatApi(_Transport transport,
      {required String? Function() tokenProvider,
      required String Function() userProvider})
      : super(
            client: Dio()..httpClientAdapter = transport,
            tokenProvider: tokenProvider,
            userProvider: userProvider);

  String chatBase = 'https://chat.example';

  @override
  String get baseUrl => chatBase;
}

ResponseBody _json(dynamic data) => ResponseBody.fromString(
      jsonEncode({'errCode': 0, 'data': data}),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json']
      },
    );

GroupFeatureContext _context(
        GroupFeatureApi api, FixtureAccountPrivilege privilege,
        {String tenantID = 'tenant-authorized'}) =>
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
                canConfigure: true,
                canManage: true,
                canOpenAgent: true,
                canViewRebateHistory: true,
                tenantID: tenantID)),
        sessionCurrent: () => true,
        onFeaturesChanged: (_) {});

void _expectSangongCredentials(RequestOptions request,
    {String? tenant = 'tenant-authorized'}) {
  expect(request.headers['Authorization'], 'Bearer chat-token');
  expect(request.headers.containsKey('token'), isFalse);
  expect(request.headers['operationID'], isNotEmpty);
  expect(request.headers['X-Tenant-Id'], tenant);
  expect(request.contentType, Headers.jsonContentType);
  expect(request.followRedirects, isFalse);
}

void _expectChatCredentials(RequestOptions request) {
  expect(request.headers['token'], 'chat-token');
  expect(request.headers.containsKey('Authorization'), isFalse);
  expect(request.headers['operationID'], isNotEmpty);
  expect(request.headers.containsKey('X-Tenant-Id'), isFalse);
  expect(request.followRedirects, isFalse);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport transport;
  late _ChatApi api;
  late FixtureAccountPrivilege privilege;
  late String token;
  late String user;

  setUp(() {
    token = 'chat-token';
    user = 'owner';
    transport = _Transport();
    api = _ChatApi(transport,
        tokenProvider: () => token, userProvider: () => user);
    privilege = FixtureAccountPrivilege();
  });

  tearDown(() => privilege.dispose());

  test('build configuration reaches the host and default runtime', () async {
    const expectedBase = String.fromEnvironment('SANGONG_TEST_EXPECTED_BASE',
        defaultValue: 'http://129.226.192.93:10008/sangong/api/v1');
    const expectedPrefix = String.fromEnvironment(
        'SANGONG_TEST_EXPECTED_PREFIX',
        defaultValue: '/sangong');
    final context = _context(api, privilege);
    final host = SangongFeatureHost(featureContext: context);
    final runtime = SangongRuntime(context);
    addTearDown(runtime.dispose);

    await runtime.admin.fetchSession();

    expect(host.pathPrefix, expectedPrefix);
    final expectedRoute = Uri.parse(expectedBase).path.endsWith('/api/v1')
        ? '$expectedBase/admin/session'
        : '$expectedBase$expectedPrefix/api/v1/admin/session';
    expect(transport.requests.single.uri.toString(), expectedRoute);
    _expectSangongCredentials(transport.requests.single);
  });

  test('unset API base preserves the Chat proxy route and credentials',
      () async {
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: '', configuredTenantId: '', pathPrefix: '/sangong');
    addTearDown(runtime.dispose);

    await runtime.admin.fetchSession();

    expect(transport.requests.single.uri.toString(),
        'https://chat.example/sangong/api/v1/admin/session');
    _expectSangongCredentials(transport.requests.single);
    expect(runtime.http.baseUrl, api.baseUrl);
  });

  test('custom base and prefix route admin and tenantless discovery together',
      () async {
    transport.respond = (request) => request.uri.path.endsWith('/entry-context')
        ? _json({
            'showAgentEntry': true,
            'tenantId': 'tenant-authorized',
            'agentImGroupId': 'group-sangong'
          })
        : _json({'round': null, 'status': 'idle'});
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: ' https://game.example/gateway/// ',
        configuredTenantId: '',
        pathPrefix: ' /proxy/sangong/ ');
    addTearDown(runtime.dispose);

    await runtime.admin.fetchSession();
    await runtime.agent.fetchEntryContext('group-sangong');

    expect(transport.requests[0].uri.toString(),
        'https://game.example/gateway/proxy/sangong/api/v1/admin/session');
    expect(transport.requests[1].uri.path,
        '/gateway/proxy/sangong/api/v1/agent/entry-context');
    expect(
        transport.requests[1].queryParameters, {'imGroupId': 'group-sangong'});
    _expectSangongCredentials(transport.requests[0]);
    _expectSangongCredentials(transport.requests[1], tenant: null);
    expect(api.baseUrl, 'https://chat.example');
  });

  test('empty prefix reaches the service API directly', () async {
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: 'https://game.example',
        configuredTenantId: '',
        pathPrefix: '/');
    addTearDown(runtime.dispose);

    await runtime.admin.fetchSession();

    expect(transport.requests.single.uri.toString(),
        'https://game.example/api/v1/admin/session');
  });

  test('production overview and existing dashboard keep their distinct routes',
      () async {
    const overview = {'totalTurnover': 123, 'reportPeriod': 'current'};
    transport.respond = (request) =>
        request.uri.path.endsWith('/me/reports/overview')
            ? _json(overview)
            : _json(sangongFixtureResponse(
                SangongCall(request.uri.path, 'GET', null, null, null)));
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: 'http://129.226.192.93:10008/sangong/api/v1/',
        configuredTenantId: ' @z8hFfDvVQP0x ',
        pathPrefix: '/legacy/proxy');
    addTearDown(runtime.dispose);

    final report = await runtime.reports.fetchOverview();
    final dashboard = await runtime.agent.fetchSangongTeamDashboard();

    expect(report, overview);
    expect(dashboard['summary']['memberCount'], 2);
    expect(transport.requests[0].uri.toString(),
        'http://129.226.192.93:10008/sangong/api/v1/me/reports/overview');
    expect(transport.requests[1].uri.path, '/sangong/api/v1/me/team/dashboard');
    for (final request in transport.requests) {
      expect(request.method, 'GET');
      _expectSangongCredentials(request);
    }
  });

  test('fixed tenant is sent for discovery without granting a business binding',
      () async {
    transport.respond = (request) => request.uri.path.endsWith('/entry-context')
        ? _json({
            'showAgentEntry': true,
            'tenantId': 'tenant-authorized',
            'agentImGroupId': 'group-sangong'
          })
        : _json({'configured': false});
    final runtime = SangongRuntime(_context(api, privilege, tenantID: ''),
        baseUrl: 'http://129.226.192.93:10008/sangong/api/v1',
        configuredTenantId: '@z8hFfDvVQP0x');
    addTearDown(runtime.dispose);

    await runtime.admin.fetchMyConfig();
    await runtime.agent.fetchEntryContext('group-sangong');

    for (final request in transport.requests) {
      _expectSangongCredentials(request, tenant: '@z8hFfDvVQP0x');
    }
    expect(runtime.http.tenantId, isNull);
    expect(runtime.http.hasTenant, isFalse);
    expect(runtime.canManage, isFalse);
    await expectLater(
        runtime.admin.fetchSession(), throwsA(isA<DioException>()));
    expect(transport.requests, hasLength(2));
  });

  test('unchanged fixed tenant cannot revive a revoked in-flight operation',
      () async {
    final opened = Completer<void>();
    final reply = Completer<ResponseBody>();
    transport.respond = (_) {
      opened.complete();
      return reply.future;
    };
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: 'http://129.226.192.93:10008/sangong/api/v1',
        configuredTenantId: '@z8hFfDvVQP0x');
    addTearDown(runtime.dispose);
    final request = runtime.admin.fetchSession();
    final rejected = expectLater(request, throwsA(isA<DioException>()));
    await opened.future;

    privilege.setAllowed(false);
    expect(runtime.http.tenantId, isNull);
    expect(runtime.canManage, isFalse);
    privilege.setAllowed(true);
    expect(runtime.http.tenantId, 'tenant-authorized');
    reply.complete(_json({'status': 'running', 'round': null}));
    await rejected;

    _expectSangongCredentials(transport.requests.single);
  });

  test('Sangong snapshot and SSE share the configured route and tenant',
      () async {
    final stream = StreamController<Uint8List>();
    final opened = Completer<void>();
    transport.respond = (request) {
      if (request.uri.path.endsWith('/events/stream')) {
        opened.complete();
        return ResponseBody(stream.stream, 200, headers: {
          Headers.contentTypeHeader: ['text/event-stream']
        });
      }
      return _json(sangongState(1));
    };
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: 'http://129.226.192.93:10008/sangong/api/v1',
        configuredTenantId: '@z8hFfDvVQP0x',
        pathPrefix: '/sangong');
    addTearDown(runtime.dispose);
    addTearDown(stream.close);

    runtime.realtime.acquire();
    await opened.future;
    await runtime.realtime.refreshSnapshot();
    final stateAccepted = Completer<void>();
    void changed() {
      if (runtime.realtime.latestState?.version == 2 &&
          !stateAccepted.isCompleted) {
        stateAccepted.complete();
      }
    }

    runtime.realtime.addListener(changed);
    stream.add(Uint8List.fromList(
        utf8.encode('event: state\ndata: ${jsonEncode(sangongState(2))}\n\n')));
    await stateAccepted.future;
    runtime.realtime.removeListener(changed);
    runtime.realtime.release();

    final snapshot = transport.requests
        .firstWhere((request) => request.uri.path.endsWith('/events/snapshot'));
    final eventStream = transport.requests
        .singleWhere((request) => request.uri.path.endsWith('/events/stream'));
    expect(snapshot.uri.toString(),
        'http://129.226.192.93:10008/sangong/api/v1/admin/events/snapshot');
    expect(eventStream.uri.toString(),
        'http://129.226.192.93:10008/sangong/api/v1/admin/events/stream');
    _expectSangongCredentials(snapshot);
    _expectSangongCredentials(eventStream);
    expect(eventStream.headers['Accept'], 'text/event-stream');
    expect(eventStream.receiveTimeout, Duration.zero);
  });

  test('custom Sangong server leaves shared group permissions on Chat',
      () async {
    transport.respond =
        (request) => request.uri.path.endsWith('/feature-capabilities')
            ? _json({
                'groupID': 'group-sangong',
                'capabilityVersion': 1,
                'sangong': {'canManage': true, 'tenantID': 'tenant-authorized'}
              })
            : _json({'round': null, 'status': 'idle'});
    final store = GroupFeatureStore(
        api: api,
        sessionCurrent: () => true,
        accountPrivilege: privilege,
        fetchGroups: (_) async => []);
    addTearDown(store.dispose);
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: 'https://game.example',
        configuredTenantId: '@z8hFfDvVQP0x',
        pathPrefix: '/sangong');
    addTearDown(runtime.dispose);

    await runtime.admin.fetchSession();
    await store.loadCapabilities('group-sangong');

    expect(transport.requests[0].uri.host, 'game.example');
    expect(transport.requests[1].uri.toString(),
        'https://chat.example/chat/groups/group-sangong/feature-capabilities');
    _expectSangongCredentials(transport.requests[0]);
    _expectChatCredentials(transport.requests[1]);
    expect(store.capabilities('group-sangong').sangong.canManage, isTrue);
  });

  for (final changedValue in ['token', 'user', 'Chat server']) {
    test(
        'custom base rejects an in-flight response after $changedValue changes',
        () async {
      final opened = Completer<void>();
      final reply = Completer<ResponseBody>();
      transport.respond = (_) {
        opened.complete();
        return reply.future;
      };
      final request = api.requestData('/sangong/api/v1/admin/session',
          baseUrlOverride: 'https://game.example', useBearerAuth: true);
      final rejected = expectLater(
          request,
          throwsA(isA<GroupFeatureException>()
              .having((error) => error.code, 'code', 'SESSION_CHANGED')));
      await opened.future;
      switch (changedValue) {
        case 'token':
          token = 'new-chat-token';
        case 'user':
          user = 'another-owner';
        case 'Chat server':
          api.chatBase = 'https://another-chat.example';
      }
      reply.complete(_json({'round': null}));
      await rejected;
      expect(transport.requests.single.uri.host, 'game.example');
      _expectSangongCredentials(transport.requests.single, tenant: null);
    });
  }

  test('custom SSE discards events after the Chat server changes', () async {
    final source = StreamController<Uint8List>();
    final opened = Completer<void>();
    transport.respond = (_) {
      opened.complete();
      return ResponseBody(source.stream, 200);
    };
    final chunks = <String>[];
    final errors = <Object>[];
    final completed = Completer<void>();
    api
        .eventStream('/sangong/api/v1/admin/events/stream',
            baseUrlOverride: 'https://game.example', useBearerAuth: true)
        .listen(chunks.add,
            onError: (Object error) => errors.add(error),
            onDone: completed.complete);
    await opened.future;
    await Future<void>.delayed(Duration.zero);
    api.chatBase = 'https://another-chat.example';
    source.add(Uint8List.fromList(utf8.encode('data: old-session\n\n')));
    await completed.future;
    await source.close();

    expect(chunks, isEmpty);
    expect(
        errors.single,
        isA<GroupFeatureException>()
            .having((error) => error.code, 'code', 'SESSION_CHANGED'));
    _expectSangongCredentials(transport.requests.single, tenant: null);
  });
}
