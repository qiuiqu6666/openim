import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/api/binding/sangong_group_tenant_api.dart';
import 'package:openim/pages/group_features/sangong/models/binding/sangong_group_tenant_state.dart';

import '../../sangong_test_support.dart';

const _groupId = '@TGS#下注群 /?%';
const _chatToken = 'current-chat-token';

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? respond;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond == null ? _json(_tenant()) : await respond!(options);
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

  String chatBase = 'https://chat.example/api';
  @override
  String get baseUrl => chatBase;
}

ResponseBody _json(dynamic body, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: ['application/json']
    });

Map<String, dynamic> _tenant({String id = _groupId, bool active = true}) => {
      'tenantId': id,
      'active': active,
      'name': '当前群厅',
      'imGroupGameId': id,
      'imGroupAdminStatsId': 'statistics-group',
      'imGroupLedgerId': 'ledger-group',
      'imBotUserId': 'bot-user',
      'myRole': 'owner',
      'canEditConfig': true,
      'canManageMembers': true,
    };

Map<String, dynamic> _errorBody(String key, String code) => key == 'error.code'
    ? {
        'error': {'code': code}
      }
    : {key: code};

TypeMatcher<GroupFeatureException> _failure(String code,
        {int? status, String? serverCode}) =>
    isA<GroupFeatureException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.statusCode, 'statusCode', status)
        .having((error) => error.serverCode, 'serverCode', serverCode);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Transport transport;
  late _ChatApi api;
  late FixtureAccountPrivilege privilege;
  late String? token;
  late String user;
  late List<String> logs;
  const lookup = SangongGroupTenantApi();

  GroupFeatureContext context({
    String groupId = _groupId,
    FixtureAccountPrivilege? access,
    bool Function()? current,
    bool Function()? capabilitiesCurrent,
    GroupFeatureContext Function()? readContext,
    GroupFeatureApi? sourceApi,
    bool groupAdmin = false,
  }) =>
      GroupFeatureContext(
        groupID: groupId,
        groupName: '三公查询测试',
        currentUserID: 'owner',
        api: sourceApi ?? api,
        accountPrivilege: access ?? privilege,
        isGroupAdmin: groupAdmin,
        sessionCurrent: current ?? () => true,
        capabilitiesCurrent: capabilitiesCurrent ?? () => true,
        readContext: readContext,
        onFeaturesChanged: (_) => fail('Tenant lookup changed group features'),
      );

  setUp(() {
    transport = _Transport();
    token = _chatToken;
    user = 'owner';
    api = _ChatApi(transport,
        tokenProvider: () => token, userProvider: () => user);
    privilege = FixtureAccountPrivilege();
    addTearDown(privilege.dispose);
    logs = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);
  });

  test('current group lookup uses encoded Chat URL and Bearer without tenant',
      () async {
    final response = {
      'errCode': 0,
      'data': {..._tenant(), 'configured': false}
    };
    final original = jsonEncode(response);
    transport.respond = (_) => _json(response);
    final scope = context();
    final capability = scope.capabilities;
    final feature = scope.features;
    final state = await lookup.fetch(scope);
    final request = transport.requests.single;
    expect(request.uri.toString(),
        '${api.baseUrl}/sangong/api/v1/admin/tenants/${Uri.encodeComponent(_groupId)}');
    expect(request.uri.fragment, isEmpty);
    expect(request.uri.query, isEmpty);
    expect(request.method, 'GET');
    expect(request.headers['Authorization'], 'Bearer $_chatToken');
    expect(request.headers.containsKey('token'), isFalse);
    expect(request.headers.containsKey('X-Tenant-Id'), isFalse);
    expect(request.headers['operationID'], isNotEmpty);
    expect(request.contentType, Headers.jsonContentType);
    expect(request.followRedirects, isFalse);
    expect(state.status, SangongGroupTenantStatus.configured);
    expect(state.tenantId, _groupId);
    expect(state.config!.configured, isTrue);
    expect(state.config!.tenantId, _groupId);
    expect(state.config!.imGroupGameId, _groupId);
    expect(state.config!.myRole, 'owner');
    expect(state.config!.canEditConfig, isTrue);
    expect(state.config!.canManageMembers, isTrue);
    expect(state.config!.imGroupAdminStatsId, 'statistics-group');
    expect(state.config!.imGroupLedgerId, 'ledger-group');
    expect(state.config!.imBotUserId, 'bot-user');
    expect(state.raw, response);
    expect(jsonEncode(response), original);
    expect(scope.capabilities, same(capability));
    expect(scope.features, same(feature));
    expect(scope.capabilities.sangong.canConfigure, isFalse);
    expect(scope.capabilities.sangong.canManage, isFalse);
    expect(scope.capabilities.sangong.tenantID, isEmpty);
    expect(logs.join('\n'), contains(request.uri.toString()));
    expect(logs.join('\n'), isNot(contains(_chatToken)));
  });

  test('explicit agent tenant may bind a different betting group', () async {
    const tenant = '@TGS#游戏群';
    transport.respond = (_) => _json(_tenant(id: tenant));
    final state =
        await lookup.fetch(context(groupId: 'agent-group'), tenantId: tenant);
    expect(state.status, SangongGroupTenantStatus.configured);
    expect(state.tenantId, tenant);
    expect(state.config!.imGroupGameId, tenant);
    expect(transport.requests.single.uri.toString(),
        '${api.baseUrl}/sangong/api/v1/admin/tenants/${Uri.encodeComponent(tenant)}');
    expect(
        transport.requests.single.headers.containsKey('X-Tenant-Id'), isFalse);
  });

  for (final active in [true, false]) {
    test('active=$active alone fills queried IDs without inventing roles',
        () async {
      transport.respond = (_) => _json({'active': active});
      final state = await lookup.fetch(context());
      expect(
          state.status,
          active
              ? SangongGroupTenantStatus.configured
              : SangongGroupTenantStatus.disabled);
      expect(state.config!.configured, isTrue);
      expect(state.tenantId, _groupId);
      expect(state.config!.imGroupGameId, _groupId);
      expect(state.config!.myRole, isEmpty);
      expect(state.config!.canEditConfig, isFalse);
      expect(state.config!.canManageMembers, isFalse);
      expect(state.raw, {'active': active});
      if (!active) expect(state.message, '当前群的三公已停用');
    });
  }

  test('owner role without permission fields keeps config permissions false',
      () async {
    transport.respond = (_) => _json({'active': true, 'myRole': 'owner'});
    final config = (await lookup.fetch(context())).config!;
    expect(config.myRole, 'owner');
    expect(config.canEditConfig, isFalse);
    expect(config.canManageMembers, isFalse);
  });

  test(
      'envelopes and nested tenant fields preserve actual binding and raw data',
      () async {
    for (final envelopeKey in ['data', 'result', 'payload']) {
      final body = {
        'errCode': 0,
        envelopeKey: {
          'active': true,
          'my_role': 'admin',
          'tenant': {
            'tenantID': _groupId,
            'im_group_game_id': _groupId,
            'can_edit_config': false,
            'can_manage_members': true,
            'name': '当前群厅',
            'message': '具体租户状态',
          }
        }
      };
      transport.respond = (_) => _json(body);
      final state = await lookup.fetch(context());
      expect(state.status, SangongGroupTenantStatus.configured);
      expect(state.message, '具体租户状态');
      expect(state.config!.myRole, 'admin');
      expect(state.config!.canEditConfig, isFalse);
      expect(state.config!.canManageMembers, isTrue);
      expect(state.config!.imGroupGameId, _groupId);
      expect(state.raw, body);
    }
  });

  test('each explicit tenant ID alias is accepted only for the requested ID',
      () async {
    for (final key in ['tenantId', 'tenantID', 'id', 'tenant_id']) {
      transport.respond = (_) => _json({'active': true, key: _groupId});
      expect((await lookup.fetch(context())).tenantId, _groupId);
      transport.respond = (_) => _json({'active': true, key: 'another-tenant'});
      await expectLater(
          lookup.fetch(context()), throwsA(_failure('INVALID_RESPONSE')));
    }
  });

  test(
      'unknown active values and malformed successful bodies are format errors',
      () async {
    for (final body in <dynamic>[
      {},
      {'active': null},
      {'active': 0},
      {'active': 1},
      {'active': 'true'},
      {'active': 'false'},
      {'active': {}},
      {'active': []},
      {'active': true, 'tenant': null},
      {'active': true, 'tenant': []},
      {
        'active': true,
        'tenant': {'active': null}
      },
      [],
      null,
    ]) {
      transport.respond = (_) => _json(body);
      await expectLater(
          lookup.fetch(context()), throwsA(_failure('INVALID_RESPONSE')));
    }
  });

  test('current-game explicit group and tenant mismatches cannot be accepted',
      () async {
    for (final body in [
      {'active': true, 'imGroupGameId': 'another-group'},
      {'active': true, 'im_group_game_id': 'another-group'},
      {'active': true, 'imGroupGameId': ''},
      {'active': true, 'imGroupGameId': null},
      {'active': true, 'tenantId': null},
      {'active': true, 'tenantId': 42},
      {'active': true, 'tenantId': _groupId, 'tenantID': 'another-tenant'},
    ]) {
      transport.respond = (_) => _json(body);
      await expectLater(
          lookup.fetch(context()), throwsA(_failure('INVALID_RESPONSE')));
    }
    transport.respond = (_) => _json(_tenant(id: 'another-tenant'));
    await expectLater(
        lookup.fetch(context(groupId: 'agent-group'),
            tenantId: 'requested-tenant'),
        throwsA(_failure('INVALID_RESPONSE')));
  });

  for (final key in ['code', 'errorCode', 'errCode', 'error.code']) {
    test('HTTP 404 exact $key TENANT_NOT_FOUND is a not-found state', () async {
      transport.respond =
          (_) => _json(_errorBody(key, 'TENANT_NOT_FOUND'), status: 404);
      final state = await lookup.fetch(context());
      expect(state.status, SangongGroupTenantStatus.notFound);
      expect(state.tenantId, _groupId);
      expect(state.config, isNull);
      expect(state.message, '当前群尚未配置三公');
    });
    test('HTTP 403 exact $key TENANT_ACCESS_DENIED is access-denied state',
        () async {
      transport.respond =
          (_) => _json(_errorBody(key, 'TENANT_ACCESS_DENIED'), status: 403);
      final state = await lookup.fetch(context());
      expect(state.status, SangongGroupTenantStatus.accessDenied);
      expect(state.tenantId, _groupId);
      expect(state.config, isNull);
      expect(state.message, '当前群已配置三公，请联系配置者授权');
    });
  }

  test('generic or inexact 404 errors preserve shared unavailable behavior',
      () async {
    for (final code in <String?>[
      null,
      'NOT_FOUND',
      'tenant_not_found',
      'TENANT_NOT_FOUND_OTHER',
      ' TENANT_NOT_FOUND ',
      'TENANT_ACCESS_DENIED',
    ]) {
      transport.respond =
          (_) => _json(code == null ? {} : {'code': code}, status: 404);
      await expectLater(
          lookup.fetch(context()),
          throwsA(_failure('SERVICE_UNAVAILABLE', status: 404, serverCode: code)
              .having((error) => error.unavailable, 'unavailable', isTrue)));
    }
  });

  test('generic or inexact 403 errors never become a recognized tenant state',
      () async {
    for (final code in <String?>[
      null,
      'FORBIDDEN',
      'tenant_access_denied',
      'TENANT_ACCESS_DENIED_OTHER',
      'TENANT_NOT_FOUND',
    ]) {
      transport.respond =
          (_) => _json(code == null ? {} : {'code': code}, status: 403);
      await expectLater(
          lookup.fetch(context()),
          throwsA(
              _failure(code ?? 'FORBIDDEN', status: 403, serverCode: code)));
    }
  });

  test('tenant error codes on HTTP 200 still throw business errors', () async {
    for (final code in ['TENANT_NOT_FOUND', 'TENANT_ACCESS_DENIED']) {
      transport.respond = (_) => _json({'code': code});
      await expectLater(lookup.fetch(context()),
          throwsA(_failure(code, status: 200, serverCode: code)));
    }
  });

  test('other HTTP failures keep actual status and existing shared error codes',
      () async {
    for (final (status, code) in <(int, String)>[
      (301, 'HTTP_301'),
      (401, 'AUTH_REQUIRED'),
      (500, 'HTTP_500'),
      (501, 'SERVICE_UNAVAILABLE'),
      (502, 'HTTP_502'),
    ]) {
      transport.respond = (_) => _json({}, status: status);
      await expectLater(
          lookup.fetch(context()), throwsA(_failure(code, status: status)));
    }
    transport.respond = (_) => _json({
          'error': {'code': 'TENANT_NOT_FOUND'}
        }, status: 503);
    await expectLater(
        lookup.fetch(context()),
        throwsA(
            _failure('HTTP_503', status: 503, serverCode: 'TENANT_NOT_FOUND')));
  });

  test('authentication business errors retain authentication semantics',
      () async {
    transport.respond = (_) => _json({'errCode': 1501}, status: 401);
    await expectLater(
        lookup.fetch(context()),
        throwsA(_failure('1501', status: 401, serverCode: '1501')
            .having((error) => error.authRequired, 'authRequired', isTrue)));
  });

  test(
      'Dio errors preserve available HTTP metadata without changing network code',
      () async {
    transport.respond = (request) => throw DioException(
          requestOptions: request,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: request,
            statusCode: 503,
            data: {
              'error': {'code': 'UPSTREAM_FAILURE'}
            },
          ),
        );
    await expectLater(
        lookup.fetch(context()),
        throwsA(_failure('NETWORK_ERROR',
            status: 503, serverCode: 'UPSTREAM_FAILURE')));
    transport.respond = (request) => throw DioException(
        requestOptions: request, type: DioExceptionType.connectionError);
    await expectLater(
        lookup.fetch(context()), throwsA(_failure('NETWORK_ERROR')));
  });

  test('missing account privilege or stale session dispatches no lookup',
      () async {
    privilege.setAllowed(false);
    await expectLater(
        lookup.fetch(context()), throwsA(_failure('PRIVILEGE_REQUIRED')));
    privilege.setAllowed(true);
    await expectLater(lookup.fetch(context(current: () => false)),
        throwsA(_failure('SESSION_CHANGED')));
    token = '';
    await expectLater(
        lookup.fetch(context()), throwsA(_failure('SESSION_CHANGED')));
    expect(transport.requests, isEmpty);
  });

  test('empty tenant ID is rejected before transport', () async {
    await expectLater(lookup.fetch(context(), tenantId: ' '),
        throwsA(_failure('INVALID_REQUEST')));
    expect(transport.requests, isEmpty);
  });

  test(
      'pending capability snapshots do not prevent privileged existence lookup',
      () async {
    final state = await lookup.fetch(context(capabilitiesCurrent: () => false));
    expect(state.status, SangongGroupTenantStatus.configured);
    expect(transport.requests, hasLength(1));
  });

  for (final change in ['session', 'token', 'user', 'base', 'api', 'group']) {
    test('in-flight lookup rejects changed $change source', () async {
      final started = Completer<void>();
      final reply = Completer<ResponseBody>();
      transport.respond = (_) {
        started.complete();
        return reply.future;
      };
      var current = true;
      GroupFeatureContext? latest;
      late GroupFeatureContext captured;
      captured = context(
          current: () => current, readContext: () => latest ?? captured);
      final task = lookup.fetch(captured);
      await started.future;
      switch (change) {
        case 'session':
          current = false;
        case 'token':
          token = 'replacement-chat-token';
        case 'user':
          user = 'another-user';
        case 'base':
          api.chatBase = 'https://another-chat.example';
        case 'api':
          latest = context(
              sourceApi: GroupFeatureApi(
                  baseUrl: api.baseUrl,
                  tokenProvider: () => token,
                  userProvider: () => user));
        case 'group':
          latest = context(groupId: 'another-group');
      }
      reply.complete(_json(_tenant()));
      await expectLater(task, throwsA(_failure('SESSION_CHANGED')));
    });
  }

  for (final regrant in [false, true]) {
    test(
        'in-flight privilege revision change rejects lookup (regrant=$regrant)',
        () async {
      final started = Completer<void>();
      final reply = Completer<ResponseBody>();
      transport.respond = (_) {
        started.complete();
        return reply.future;
      };
      final task = lookup.fetch(context());
      await started.future;
      privilege.setAllowed(false);
      if (regrant) privilege.setAllowed(true);
      reply
          .complete(_json(_errorBody('code', 'TENANT_NOT_FOUND'), status: 404));
      await expectLater(task, throwsA(_failure('PRIVILEGE_CHANGED')));
    });
  }

  test('in-flight replacement of the privilege source is rejected', () async {
    final started = Completer<void>();
    final reply = Completer<ResponseBody>();
    transport.respond = (_) {
      started.complete();
      return reply.future;
    };
    GroupFeatureContext? latest;
    late GroupFeatureContext captured;
    captured = context(readContext: () => latest ?? captured);
    final task = lookup.fetch(captured);
    await started.future;
    final replacement = FixtureAccountPrivilege();
    addTearDown(replacement.dispose);
    latest = context(access: replacement);
    reply.complete(_json(_tenant()));
    await expectLater(task, throwsA(_failure('PRIVILEGE_CHANGED')));
  });

  test('ordinary shared requests keep their existing token header', () async {
    await api.requestData('/shared');
    final request = transport.requests.single;
    expect(request.headers['token'], _chatToken);
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.headers.containsKey('X-Tenant-Id'), isFalse);
  });

  Map<String, dynamic> writeBody() => {
        'imGroupGameId': _groupId,
        'imBotUserId': 'bot-user',
        'name': '',
        'imGroupAdminStatsId': '',
        'imGroupLedgerId': '',
        'imGroupWaterId': '',
      };

  void expectWriteCredentials(RequestOptions request) {
    expect(request.headers['Authorization'], 'Bearer $_chatToken');
    expect(request.headers.containsKey('token'), isFalse);
    expect(request.headers.containsKey('X-Tenant-Id'), isFalse);
    expect(request.contentType, Headers.jsonContentType);
    expect(request.followRedirects, isFalse);
  }

  test('native group admin creates through Chat POST201 with raw body and DTO',
      () async {
    final body = writeBody();
    final bodyBefore = jsonEncode(body);
    final dto = _tenant()
      ..remove('myRole')
      ..remove('canEditConfig')
      ..remove('canManageMembers');
    final response = {'ok': true, 'data': dto};
    final responseBefore = jsonEncode(response);
    transport.respond = (_) => _json(response, status: 201);
    final scope = context(groupAdmin: true);
    final state = await lookup.create(scope, body: body);
    final request = transport.requests.single;
    expect(request.method, 'POST');
    expect(
        request.uri.toString(), '${api.baseUrl}/sangong/api/v1/admin/tenants');
    expect(request.data, body);
    expectWriteCredentials(request);
    expect(state.status, SangongGroupTenantStatus.configured);
    expect(state.config!.configured, isTrue);
    expect(state.config!.myRole, isEmpty);
    expect(state.config!.canEditConfig, isFalse);
    expect(state.config!.canManageMembers, isFalse);
    expect(state.raw, response);
    expect(jsonEncode(body), bodyBefore);
    expect(jsonEncode(response), responseBefore);
    expect(scope.capabilities.sangong.canConfigure, isFalse);
    expect(scope.capabilities.sangong.canManage, isFalse);
  });

  for (final active in [true, false]) {
    test(
        'PUT200 complete config without configured or permissions has active=$active',
        () async {
      final body = writeBody()..remove('imGroupGameId');
      final original = jsonEncode(body);
      final dto = _tenant(active: active)
        ..remove('canEditConfig')
        ..remove('canManageMembers');
      transport.respond = (_) => _json({'errCode': 0, 'data': dto});
      final scope = context();
      final state = await lookup.update(scope, tenantId: _groupId, body: body);
      final request = transport.requests.single;
      expect(request.method, 'PUT');
      expect(request.uri.toString(),
          '${api.baseUrl}/sangong/api/v1/admin/tenants/${Uri.encodeComponent(_groupId)}');
      expect(request.data, body);
      expectWriteCredentials(request);
      expect(
          state.status,
          active
              ? SangongGroupTenantStatus.configured
              : SangongGroupTenantStatus.disabled);
      expect(state.config!.configured, isTrue);
      expect(state.config!.myRole, 'owner');
      expect(state.config!.canEditConfig, isFalse);
      expect(state.config!.canManageMembers, isFalse);
      expect(jsonEncode(body), original);
      expect(scope.isGroupAdmin, isFalse);
      expect(scope.capabilities.sangong.canConfigure, isFalse);
    });
  }

  test(
      'create requires native admin, current game group and a bot before dispatch',
      () async {
    await expectLater(lookup.create(context(), body: writeBody()),
        throwsA(_failure('GROUP_ADMIN_REQUIRED')));
    for (final body in [
      writeBody()..remove('imGroupGameId'),
      {...writeBody(), 'imGroupGameId': 'another-group'},
      writeBody()..remove('imBotUserId'),
      {...writeBody(), 'imBotUserId': ''},
      {...writeBody(), 'imBotUserId': ' '},
      {...writeBody(), 'imBotUserId': null},
    ]) {
      await expectLater(lookup.create(context(groupAdmin: true), body: body),
          throwsA(_failure('INVALID_REQUEST')));
    }
    expect(transport.requests, isEmpty);
  });

  test('update cannot target or move another betting group', () async {
    await expectLater(
        lookup.update(context(), tenantId: 'another-group', body: writeBody()),
        throwsA(_failure('INVALID_REQUEST')));
    for (final body in [
      {...writeBody(), 'imGroupGameId': 'another-group'},
      {...writeBody(), 'imGroupGameId': null},
      {...writeBody(), 'im_group_game_id': 'another-group'},
    ]) {
      await expectLater(
          lookup.update(context(), tenantId: _groupId, body: body),
          throwsA(_failure('INVALID_REQUEST')));
    }
    expect(transport.requests, isEmpty);
  });

  test('create never confirms malformed, rejected or incomplete POST201 bodies',
      () async {
    for (final response in <dynamic>[
      _tenant(),
      {'ok': false, 'data': _tenant()},
      {'ok': 'true', 'data': _tenant()},
      {
        'ok': true,
        'data': {'active': true}
      },
      {'ok': true, 'data': _tenant(active: false)},
      {
        'ok': true,
        'data': {..._tenant(), 'active': 'true'}
      },
      {'ok': true, 'data': _tenant()..remove('imBotUserId')},
      {'ok': true, 'data': _tenant()..remove('imGroupGameId')},
      {'ok': true, 'data': _tenant(id: 'another-group')},
    ]) {
      transport.respond = (_) => _json(response, status: 201);
      await expectLater(
          lookup.create(context(groupAdmin: true), body: writeBody()),
          throwsA(_failure('UNKNOWN_RESULT').having(
              (error) => error.unknownResult, 'unknownResult', isTrue)));
    }
  });

  test(
      'update rejects incomplete PUT200 configuration instead of reporting success',
      () async {
    for (final response in <dynamic>[
      {'active': true},
      _tenant()..remove('active'),
      {..._tenant(), 'active': null},
      {..._tenant(), 'active': 'false'},
      _tenant()..remove('imBotUserId'),
      _tenant(id: 'another-group'),
      {'ok': false, 'data': _tenant()},
    ]) {
      transport.respond = (_) => _json(response);
      await expectLater(
          lookup.update(context(), tenantId: _groupId, body: writeBody()),
          throwsA(_failure('UNKNOWN_RESULT').having(
              (error) => error.unknownResult, 'unknownResult', isTrue)));
    }
  });

  for (final method in ['POST', 'PUT']) {
    Future<SangongGroupTenantState> write(GroupFeatureContext scope) =>
        method == 'POST'
            ? lookup.create(scope, body: writeBody())
            : lookup.update(scope, tenantId: _groupId, body: writeBody());

    test('$method propagates known write errors with HTTP/backend metadata',
        () async {
      for (final (status, serverCode, code) in <(int, String, String)>[
        (409, 'TENANT_EXISTS', 'TENANT_EXISTS'),
        (422, 'GAME_GROUP_IMMUTABLE', 'GAME_GROUP_IMMUTABLE'),
        (403, 'TENANT_ACCESS_DENIED', 'TENANT_ACCESS_DENIED'),
        (404, 'TENANT_NOT_FOUND', 'SERVICE_UNAVAILABLE'),
      ]) {
        transport.respond = (_) => _json({'code': serverCode}, status: status);
        await expectLater(write(context(groupAdmin: true)),
            throwsA(_failure(code, status: status, serverCode: serverCode)));
      }
      transport.respond = (request) => throw DioException(
          requestOptions: request, type: DioExceptionType.connectionError);
      await expectLater(
          write(context(groupAdmin: true)),
          throwsA(_failure('UNKNOWN_RESULT').having(
              (error) => error.unknownResult, 'unknownResult', isTrue)));
    });

    test('$method cannot bypass account privilege or session checks', () async {
      privilege.setAllowed(false);
      await expectLater(write(context(groupAdmin: true)),
          throwsA(_failure('PRIVILEGE_REQUIRED')));
      privilege.setAllowed(true);
      await expectLater(write(context(groupAdmin: true, current: () => false)),
          throwsA(_failure('SESSION_CHANGED')));
      expect(transport.requests, isEmpty);
    });

    for (final change in ['session', 'privilege', 'base']) {
      test('$method discards a completed write after $change changes',
          () async {
        final started = Completer<void>();
        final reply = Completer<ResponseBody>();
        transport.respond = (_) {
          started.complete();
          return reply.future;
        };
        var current = true;
        final task = write(context(groupAdmin: true, current: () => current));
        await started.future;
        if (change == 'session') current = false;
        if (change == 'privilege') privilege.setAllowed(false);
        if (change == 'base') api.chatBase = 'https://changed-chat.example';
        reply.complete(_json({'ok': true, 'data': _tenant()},
            status: method == 'POST' ? 201 : 200));
        await expectLater(
            task,
            throwsA(_failure(change == 'privilege'
                ? 'PRIVILEGE_CHANGED'
                : 'SESSION_CHANGED')));
      });
    }
  }

  test('create cannot publish success after native group admin is revoked',
      () async {
    final started = Completer<void>();
    final reply = Completer<ResponseBody>();
    transport.respond = (_) {
      started.complete();
      return reply.future;
    };
    GroupFeatureContext? latest;
    late GroupFeatureContext captured;
    captured = context(groupAdmin: true, readContext: () => latest ?? captured);
    final task = lookup.create(captured, body: writeBody());
    await started.future;
    latest = context(groupAdmin: false);
    reply.complete(_json({'ok': true, 'data': _tenant()}, status: 201));
    await expectLater(task, throwsA(_failure('GROUP_ADMIN_CHANGED')));
  });
}
