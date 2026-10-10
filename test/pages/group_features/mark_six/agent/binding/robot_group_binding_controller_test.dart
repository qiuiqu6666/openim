import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/mark_six/agent/binding/robot_group_binding.dart';
import 'package:openim/pages/group_features/mark_six/agent/binding/robot_group_binding_controller.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';

const _groupID = '@TGS#代理/群?机器人';
const _chatToken = 'current-chat-token';

ResponseBody _json(dynamic value, {int status = 200}) =>
    ResponseBody.fromString(jsonEncode(value), status, headers: {
      Headers.contentTypeHeader: ['application/json'],
    });

Map<String, dynamic> _binding({
  String groupID = _groupID,
  bool bound = true,
  bool enabled = true,
}) =>
    {
      'groupId': groupID,
      'bound': bound,
      'enabled': enabled,
      'machineCodeMasked': 'AB***89',
    };

Map<String, dynamic> _envelope(Map<String, dynamic> data) => {
      'code': 0,
      'message': 'ok',
      'data': data,
    };

class _Transport implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  FutureOr<ResponseBody> Function(RequestOptions)? respond;
  dynamic body = _envelope(_binding());
  int status = 200;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return respond == null
        ? _json(body, status: status)
        : await respond!(options);
  }

  @override
  void close({bool force = false}) {}
}

class _Fixture {
  _Fixture({this.groupID = _groupID}) {
    api = GroupFeatureApi(
      client: dio,
      baseUrl: 'https://chat.example/api',
      tokenProvider: () => token,
      userProvider: () => userID,
    );
    context = GroupFeatureContext(
      groupID: groupID,
      groupName: '代理绑定测试',
      currentUserID: userID,
      api: api,
      gameType: GroupGameType.markSixAgent,
      sessionCurrent: () => active,
      // Binding is a session read even when private capabilities are stale.
      capabilitiesCurrent: () => false,
      reloadCapabilities: (_) => throw StateError('Unexpected capability read'),
      onFeaturesChanged: (_) => fail('Binding changed public group features'),
    );
    controller = RobotGroupBindingController(context);
    transport.body = _envelope(_binding(groupID: groupID));
  }

  final String groupID;
  final _Transport transport = _Transport();
  late final Dio dio = Dio()..httpClientAdapter = transport;
  late final GroupFeatureApi api;
  late final GroupFeatureContext context;
  late final RobotGroupBindingController controller;
  bool active = true;
  String? token = _chatToken;
  String userID = 'current-user';
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    dio.close(force: true);
  }
}

Future<void> _waitForRequests(_Transport transport, int count) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    if (transport.requests.length >= count) return;
    await Future<void>.delayed(Duration.zero);
  }
  expect(transport.requests, hasLength(count));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  _Fixture fixture({String groupID = _groupID}) {
    final value = _Fixture(groupID: groupID);
    addTearDown(value.dispose);
    return value;
  }

  test('binding model preserves bound independently of enabled', () {
    for (final bound in [false, true]) {
      final data = _binding(bound: bound, enabled: false);
      final before = jsonEncode(data);
      final value = RobotGroupBinding.fromJson(data, expectedGroupID: _groupID);
      expect(value.groupID, _groupID);
      expect(value.bound, bound);
      expect(value.enabled, isFalse);
      expect(value.machineCodeMasked, 'AB***89');
      expect(jsonEncode(data), before);
    }
  });

  test('binding model rejects a different or missing group', () {
    for (final data in [
      _binding(groupID: 'another-group'),
      _binding()..remove('groupId'),
      {..._binding(), 'groupId': 17},
    ]) {
      expect(() => RobotGroupBinding.fromJson(data, expectedGroupID: _groupID),
          throwsFormatException);
    }
  });

  for (final key in ['bound', 'enabled']) {
    test('binding model rejects nonboolean $key', () {
      for (final invalid in [null, 'true', 'false', 0, 1]) {
        expect(
            () => RobotGroupBinding.fromJson({..._binding(), key: invalid},
                expectedGroupID: _groupID),
            throwsFormatException);
      }
      final missing = _binding()..remove(key);
      expect(
          () => RobotGroupBinding.fromJson(missing, expectedGroupID: _groupID),
          throwsFormatException);
    });
  }

  test('binding model accepts absent mask and rejects an invalid mask', () {
    for (final data in [
      _binding()..remove('machineCodeMasked'),
      {..._binding(), 'machineCodeMasked': null},
    ]) {
      expect(
          RobotGroupBinding.fromJson(data, expectedGroupID: _groupID)
              .machineCodeMasked,
          isEmpty);
    }
    expect(
        () => RobotGroupBinding.fromJson(
            {..._binding(), 'machineCodeMasked': 123},
            expectedGroupID: _groupID),
        throwsFormatException);
  });

  test('lookup unwraps code-zero data and uses encoded Chat path and headers',
      () async {
    final value = fixture();
    expect(value.controller.binding, isNull);
    expect(value.transport.requests, isEmpty);
    expect(value.context.capabilities.markSix.canOpenAgent, isFalse);
    expect(value.context.capabilitiesCurrent(), isFalse);
    await value.controller.load();

    final request = value.transport.requests.single;
    expect(request.uri.toString(),
        '${value.api.baseUrl}/me/robot/groups/${Uri.encodeComponent(_groupID)}');
    expect(request.uri.fragment, isEmpty);
    expect(request.uri.query, isEmpty);
    expect(request.method, 'GET');
    expect(request.headers['token'], _chatToken);
    expect(request.headers['operationID'], isNotEmpty);
    expect(request.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('x-group-id')));
    expect(request.headers.containsKey('Authorization'), isFalse);
    expect(request.cancelToken, isNotNull);
    expect(request.contentType, Headers.jsonContentType);
    expect(request.followRedirects, isFalse);
    expect(value.controller.binding!.groupID, _groupID);
    expect(value.controller.binding!.machineCodeMasked, 'AB***89');
    expect(value.controller.binding!.bound, isTrue);
    expect(value.controller.loading, isFalse);
    expect(value.controller.error, isNull);
  });

  for (final bound in [false, true]) {
    test('lookup keeps bound=$bound when enabled is false', () async {
      final value = fixture();
      value.transport.body = _envelope(_binding(bound: bound, enabled: false));
      await value.controller.load();
      expect(value.controller.binding!.bound, bound);
      expect(value.controller.binding!.enabled, isFalse);
      expect(value.controller.bound, bound);
      expect(value.controller.error, isNull);
    });
  }

  test('concurrent loads share the pending request', () async {
    final value = fixture();
    final response = Completer<ResponseBody>();
    value.transport.respond = (_) => response.future;
    final first = value.controller.load();
    final second = value.controller.load();
    expect(second, same(first));
    expect(value.controller.loading, isTrue);
    await _waitForRequests(value.transport, 1);
    expect(value.transport.requests, hasLength(1));
    response.complete(_json(_envelope(_binding())));
    await Future.wait([first, second]);
    expect(value.controller.binding!.bound, isTrue);
    expect(value.controller.loading, isFalse);
  });

  test('completed reads and a new chat owner fetch fresh binding results',
      () async {
    final value = fixture();
    await value.controller.load();
    value.transport.body = _envelope(_binding(bound: false, enabled: false));
    await value.controller.load();
    expect(value.transport.requests, hasLength(2));
    expect(value.controller.binding!.bound, isFalse);

    final next = RobotGroupBindingController(value.context);
    addTearDown(next.dispose);
    value.transport.body = _envelope(_binding(enabled: false));
    await next.load();
    expect(value.transport.requests, hasLength(3));
    expect(next.binding!.bound, isTrue);
    expect(next.binding!.enabled, isFalse);
  });

  test('failed envelope does not accept its apparent binding data', () async {
    final value = fixture();
    value.transport.body = {
      'code': 500,
      'message': 'binding service failed',
      'data': _binding(),
    };
    await value.controller.load();
    expect(value.controller.binding, isNull);
    expect(value.controller.bound, isFalse);
    expect(value.controller.error, contains('binding service failed'));
    expect(value.controller.loading, isFalse);

    value.transport.body = _envelope(_binding());
    await value.controller.load();
    expect(value.controller.error, isNull);
    expect(value.controller.binding!.bound, isTrue);
    expect(value.transport.requests, hasLength(2));
  });

  test('HTTP failure and network failure leave binding unavailable', () async {
    final value = fixture();
    value.transport.status = 503;
    await value.controller.load();
    expect(value.controller.binding, isNull);
    expect(value.controller.error, isNotEmpty);
    expect(value.controller.loading, isFalse);

    value.transport.respond = (request) => throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
          error: StateError('connection lost'),
        );
    await value.controller.load();
    expect(value.controller.binding, isNull);
    expect(value.controller.error, contains('网络连接失败'));
    expect(value.controller.loading, isFalse);
  });

  test('mismatched and malformed successful data fail closed', () async {
    final value = fixture();
    for (final data in [
      _binding(groupID: 'other-group'),
      {..._binding(), 'bound': 'true'},
      {..._binding(), 'enabled': 1},
    ]) {
      value.transport.body = _envelope(data);
      await value.controller.load();
      expect(value.controller.binding, isNull);
      expect(value.controller.bound, isFalse);
      expect(value.controller.error, isNotEmpty);
      expect(value.controller.loading, isFalse);
    }
  });

  test('session invalidation ignores a late successful reply', () async {
    final value = fixture();
    final response = Completer<ResponseBody>();
    value.transport.respond = (_) => response.future;
    var notifications = 0;
    value.controller.addListener(() => notifications++);
    final pending = value.controller.load();
    await _waitForRequests(value.transport, 1);
    final before = notifications;
    value.active = false;
    response.complete(_json(_envelope(_binding())));
    await pending;
    expect(value.controller.current, isFalse);
    expect(value.controller.bound, isFalse);
    expect(value.controller.binding, isNull);
    expect(value.controller.error, isNull);
    expect(notifications, before);
    await value.controller.load();
    expect(value.transport.requests, hasLength(1));
  });

  for (final identity in ['token', 'user']) {
    test('Chat $identity changes reject a pending binding reply', () async {
      final value = fixture();
      final response = Completer<ResponseBody>();
      value.transport.respond = (_) => response.future;
      final pending = value.controller.load();
      await _waitForRequests(value.transport, 1);
      if (identity == 'token') {
        value.token = 'new-chat-token';
      } else {
        value.userID = 'new-user';
      }
      response.complete(_json(_envelope(_binding())));
      await pending;
      expect(value.controller.binding, isNull);
      expect(value.controller.bound, isFalse);
      expect(value.controller.error, contains('登录状态已变化'));
      expect(value.controller.loading, isFalse);
    });
  }

  test(
      'dispose cancels pending lookup and ignores late replies without notifying',
      () async {
    final value = fixture();
    final response = Completer<ResponseBody>();
    value.transport.respond = (_) => response.future;
    var notifications = 0;
    value.controller.addListener(() => notifications++);
    final pending = value.controller.load();
    await _waitForRequests(value.transport, 1);
    final before = notifications;
    value.dispose();
    expect(value.transport.requests.single.cancelToken!.isCancelled, isTrue);
    response.complete(_json(_envelope(_binding())));
    await pending;
    expect(value.controller.current, isFalse);
    expect(value.controller.binding, isNull);
    expect(value.controller.error, isNull);
    expect(notifications, before);
    await value.controller.load();
    expect(value.transport.requests, hasLength(1));
  });

  test('background cancels stale lookup and resume reads current binding',
      () async {
    final value = fixture();
    final oldResponse = Completer<ResponseBody>();
    value.transport.respond = (_) => oldResponse.future;
    final oldPending = value.controller.load();
    await _waitForRequests(value.transport, 1);
    final oldRequest = value.transport.requests.single;

    value.controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(oldRequest.cancelToken!.isCancelled, isTrue);
    expect(value.controller.loading, isFalse);
    expect(value.controller.binding, isNull);
    expect(value.controller.error, isNull);
    await value.controller.load();
    expect(value.transport.requests, hasLength(1));

    value.transport.respond =
        (_) => _json(_envelope(_binding(bound: false, enabled: false)));
    value.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await value.controller.load();
    expect(value.transport.requests, hasLength(2));
    expect(value.controller.binding!.bound, isFalse);
    oldResponse.complete(_json(_envelope(_binding())));
    await oldPending;
    expect(value.controller.binding!.bound, isFalse);
    expect(value.controller.error, isNull);
    expect(value.controller.loading, isFalse);

    value.transport.body = _envelope(_binding(enabled: false));
    value.transport.respond = null;
    value.controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await value.controller.load();
    expect(value.transport.requests, hasLength(3));
    expect(value.controller.binding!.bound, isTrue);
    expect(value.controller.binding!.enabled, isFalse);
  });

  test('empty group and inactive session never start a lookup', () async {
    final empty = fixture(groupID: '');
    await empty.controller.load();
    expect(empty.transport.requests, isEmpty);
    expect(empty.controller.loading, isFalse);
    final inactive = fixture()..active = false;
    await inactive.controller.load();
    expect(inactive.transport.requests, isEmpty);
    expect(inactive.controller.current, isFalse);
  });

  test('controller created in background waits for the binding resume event',
      () async {
    final binding = WidgetsBinding.instance;
    // Registered before the fixture so its observer is disposed first.
    addTearDown(() =>
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed));
    binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final value = fixture();
    final response = Completer<ResponseBody>();
    value.transport.respond = (_) => response.future;

    await value.controller.load();
    expect(value.transport.requests, isEmpty);
    expect(value.controller.loading, isFalse);
    expect(value.controller.binding, isNull);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(value.controller.loading, isTrue);
    await _waitForRequests(value.transport, 1);
    final pending = value.controller.load();
    expect(value.transport.requests, hasLength(1));
    response.complete(_json(_envelope(_binding())));
    await pending;
    expect(value.transport.requests, hasLength(1));
    expect(value.controller.binding!.bound, isTrue);
    expect(value.controller.loading, isFalse);
    expect(value.controller.error, isNull);
  });
}
