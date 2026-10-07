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

void _expectSangongCredentials(RequestOptions request) {
  expect(request.headers['Authorization'], 'Bearer chat-token');
  expect(request.headers.containsKey('token'), isFalse);
  expect(request.headers['operationID'], isNotEmpty);
  expect(request.headers.containsKey('X-Tenant-Id'), isFalse);
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
  late String token, user;
  setUp(() {
    token = 'chat-token';
    user = 'owner';
    transport = _Transport();
    api = _ChatApi(transport,
        tokenProvider: () => token, userProvider: () => user);
    privilege = FixtureAccountPrivilege();
  });
  tearDown(() => privilege.dispose());

  for (final destination in [
    (
      '',
      '/sangong',
      'https://chat.example/sangong/api/v2/groups/group-sangong/snapshot'
    ),
    (
      'https://game.example',
      '/game',
      'https://game.example/game/api/v2/groups/group-sangong/snapshot'
    ),
    (
      'https://game.example/sangong/api/v2',
      '/ignored',
      'https://game.example/sangong/api/v2/groups/group-sangong/snapshot'
    ),
    (
      'https://game.example',
      '',
      'https://game.example/api/v2/groups/group-sangong/snapshot'
    ),
  ]) {
    test('v2 destination ${destination.$1} ${destination.$2}', () async {
      final runtime = SangongRuntime(_context(api, privilege),
          baseUrl: destination.$1, pathPrefix: destination.$2);
      addTearDown(runtime.dispose);
      await runtime.admin.fetchSession();
      expect(transport.requests.single.uri.toString(), destination.$3);
      _expectSangongCredentials(transport.requests.single);
    });
  }
  test('default build uses current Chat service and host prefix', () async {
    final context = _context(api, privilege);
    final host = SangongFeatureHost(featureContext: context);
    final runtime = SangongRuntime(context);
    addTearDown(runtime.dispose);
    await runtime.admin.fetchSession();
    expect(host.pathPrefix, '/sangong');
    expect(transport.requests.single.uri.toString(),
        'https://chat.example/sangong/api/v2/groups/group-sangong/snapshot');
    _expectSangongCredentials(transport.requests.single);
  });
  test(
      'agent discovery uses the same destination and cannot borrow fixed tenant',
      () async {
    transport.respond = (request) => _json({
          'ok': true,
          'data': {
            'agentImGroupId': 'group-sangong',
            'agentImUserId': 'owner',
            'tenantId': 'bound-game',
            'showAgentEntry': true,
            'agent': {'userId': 19, 'balance': 100},
          }
        });
    final runtime = SangongRuntime(_context(api, privilege, tenantID: ''),
        baseUrl: 'https://game.example',
        pathPrefix: '/game',
        configuredTenantId: 'must-not-select-account');
    addTearDown(runtime.dispose);
    final entry = await runtime.agent.fetchEntryContext('group-sangong');
    expect(entry.tenantId, 'bound-game');
    expect(runtime.http.hasTenant, isFalse);
    expect(transport.requests.single.uri.path,
        '/game/api/v2/agent-groups/group-sangong/context');
    _expectSangongCredentials(transport.requests.single);
    await expectLater(
        runtime.admin.fetchSession(), throwsA(isA<DioException>()));
    expect(transport.requests.length, 1);
  });
  test('private operation cannot survive an equally privileged tenant switch',
      () async {
    final reply = Completer<ResponseBody>();
    transport.respond = (_) => reply.future;
    final runtime = SangongRuntime(_context(api, privilege), baseUrl: '');
    addTearDown(runtime.dispose);
    final request = runtime.admin.fetchSession();
    final rejected = expectLater(request, throwsA(isA<DioException>()));
    while (transport.requests.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    runtime.updateContext(_context(api, privilege, tenantID: 'tenant-b'));
    reply.complete(_json({'round': null, 'status': 'idle'}));
    await rejected;
    expect(transport.requests.length, 1);
  });
  test('Chat capability requests retain native token credentials', () async {
    transport.respond =
        (_) => _json({'groupID': 'group-sangong', 'capabilityVersion': 1});
    final store = GroupFeatureStore(
        api: api, sessionCurrent: () => true, fetchGroups: (_) async => []);
    addTearDown(store.dispose);
    await store.loadCapabilities('group-sangong');
    _expectChatCredentials(transport.requests.single);
  });
  test('obsolete version base fails explicitly', () async {
    final runtime = SangongRuntime(_context(api, privilege),
        baseUrl: 'https://game.example/sangong/api/v1');
    addTearDown(runtime.dispose);
    await expectLater(
        runtime.admin.fetchSession(), throwsA(isA<DioException>()));
    expect(transport.requests, isEmpty);
  });
}
