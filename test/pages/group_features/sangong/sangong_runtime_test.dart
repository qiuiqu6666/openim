import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'sangong_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('config reads merge, cache and cannot overwrite a newer save',
      (tester) async {
    final api = SangongTestApi();
    final gate = Completer<dynamic>();
    api.respond = (_) => gate.future;
    final runtime = sangongTestRuntime(sangongTestContext(api, tenantID: ''));
    addTearDown(runtime.dispose);
    final first = runtime.config.refreshFromNetwork();
    final second = runtime.config.refreshFromNetwork();
    expect(identical(first, second), isTrue);
    await flushSangong(tester);
    expect(api.count('/my-config'), 1);
    await runtime.config
        .applySaved(SangongMyConfig.fromJson(sangongConfig(name: '新厅')));
    gate.complete(sangongConfig(name: '旧厅'));
    await completeSangongRequest(tester, first);
    expect(runtime.config.config.name, '新厅');
    await completeSangongRequest(tester, runtime.config.refreshFromNetwork());
    expect(api.count('/my-config'), 1);
    expect(runtime.http.tenantId, 'tenant-authorized');
  });
  testWidgets(
      'group ID is never an authorized tenant; group binding is checked',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => sangongConfig(tenant: '');
    final runtime = sangongTestRuntime(sangongTestContext(api, tenantID: ''));
    addTearDown(runtime.dispose);
    await completeSangongRequest(tester, runtime.config.refreshFromNetwork());
    expect(runtime.http.tenantId, isNull);
    expect(runtime.canManage, isFalse);
    await runtime.config.applySaved(
        SangongMyConfig.fromJson(sangongConfig(group: 'another-group')));
    expect(runtime.http.tenantId, isNull);
  });
  testWidgets('cached owner config cannot restore revoked private capabilities',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    await runtime.config.applySaved(SangongMyConfig.fromJson(sangongConfig()));
    expect(runtime.canManage, isTrue);
    runtime.updateContext(sangongTestContext(api,
        capabilityVersion: 2,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false,
        tenantID: ''));
    expect(runtime.http.hasTenant, isFalse);
    expect(runtime.config.hasCachedConfig, isFalse);
    await runtime.config.applySaved(SangongMyConfig.fromJson(sangongConfig()));
    expect(runtime.canManage, isFalse);
    expect(runtime.canOpenAgent, isFalse);
    await rejectSangongRequest(
        tester, runtime.admin.fetchSession(), isA<Exception>());
    expect(api.calls, isEmpty);
  });
  testWidgets('first configuration works before group game is enabled',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => throw const GroupFeatureException('当前群未登记',
          code: 'SERVICE_UNAVAILABLE',
          statusCode: 404,
          serverCode: 'TENANT_NOT_FOUND');
    final runtime = SangongRuntime(sangongTestContext(api,
        enabled: false, canManage: false, canOpenAgent: false, tenantID: ''));
    addTearDown(runtime.dispose);
    await completeSangongRequest(tester, runtime.ensureManageBinding());
    expect(api.count('/my-config'), 0);
    expect(runtime.groupTenant.state?.status.name, 'notFound');
    expect(runtime.canConfigure, isTrue);
    expect(runtime.canManage, isFalse);
    expect(runtime.config.config.configured, isFalse);
  });
  testWidgets('account change discards an outstanding configuration response',
      (tester) async {
    var current = true;
    final api = SangongTestApi();
    final gate = Completer<dynamic>();
    api.respond = (_) => gate.future;
    final runtime = sangongTestRuntime(
        sangongTestContext(api, tenantID: '', current: () => current));
    addTearDown(runtime.dispose);
    final result = runtime.config.refreshFromNetwork();
    final expectation = expectLater(result, throwsA(isA<Exception>()));
    await flushSangong(tester);
    current = false;
    gate.complete(sangongConfig());
    await flushSangong(tester);
    await expectation;
    expect(runtime.config.hasCachedConfig, isFalse);
    expect(runtime.http.tenantId, isNull);
  });
  testWidgets(
      'stale capability epoch rejects a private route before and after a pending request',
      (tester) async {
    var authorized = true;
    final api = SangongTestApi();
    final gate = Completer<dynamic>();
    api.respond = (_) => gate.future;
    final runtime = sangongTestRuntime(
        sangongTestContext(api, capabilitiesCurrent: () => authorized));
    addTearDown(runtime.dispose);
    final request = runtime.admin.fetchSession();
    final expectation = expectLater(request, throwsA(isA<DioException>()));
    await flushSangong(tester);
    authorized = false;
    gate.complete({'status': 'running', 'round': null});
    await flushSangong(tester);
    await expectation;
    expect(runtime.canManage, isFalse);
    expect(runtime.canConfigure, isFalse);
    expect(runtime.canOpenAgent, isFalse);
    await rejectSangongRequest(
        tester, runtime.admin.fetchSession(), isA<DioException>());
    expect(api.count('/session'), 1);
  });
  testWidgets('history requires both private capability and group entry',
      (tester) async {
    final api = SangongTestApi();
    final runtime =
        sangongTestRuntime(sangongTestContext(api, canViewHistory: false));
    addTearDown(runtime.dispose);
    expect(runtime.canOpenAgent, isTrue);
    expect(runtime.canViewRebateHistory, isFalse);
    await rejectSangongRequest(
        tester,
        runtime.agent.fetchSangongMemberDaily(imUserId: 'owner'),
        isA<DioException>());
    expect(api.calls, isEmpty);
  });
  testWidgets(
      'business failure cannot publish a group summary or become a successful write',
      (tester) async {
    final changes = <Map<String, dynamic>>[];
    final api = SangongTestApi()
      ..respond = (_) => {
            'data': {
              'ok': false,
              'message': '操作失败',
              'groupFeatures': {'schemaVersion': 1, 'revision': 3}
            }
          };
    final runtime = sangongTestRuntime(
        sangongTestContext(api, onFeaturesChanged: changes.add));
    addTearDown(runtime.dispose);
    await rejectSangongRequest(
        tester, runtime.admin.startSession(), isA<DioException>());
    expect(changes, isEmpty);
  });
  testWidgets(
      'one stream and one snapshot serve multiple owners; no 15-second polling',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    runtime.realtime.acquire();
    runtime.realtime.acquire();
    await flushSangong(tester);
    expect(runtime.realtime.ownerCount, 2);
    expect(api.streamStarts, 1);
    expect(api.count('/events/snapshot'), 1);
    api.streams.last
        .add('event: state\ndata: ${jsonEncode(sangongState(3))}\n\n');
    await tester.pump();
    api.streams.last
        .add('event: state\ndata: ${jsonEncode(sangongState(2))}\n\n');
    await tester.pump();
    expect(runtime.realtime.latestState!.version, 3);
    await tester.pump(const Duration(seconds: 16));
    expect(api.count('/events/snapshot'), 1);
    runtime.realtime.release();
    expect(api.streamStops, 0);
    runtime.realtime.release();
    await tester.pump();
    expect(api.streamStops, 1);
    expect(runtime.realtime.ownerCount, 0);
  });
  testWidgets('background stops SSE and resume calibrates once',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    runtime.realtime.acquire();
    await flushSangong(tester);
    runtime.realtime.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump();
    expect(api.streamStops, 1);
    await tester.pump(const Duration(seconds: 60));
    expect(api.streamStarts, 1);
    runtime.realtime.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await flushSangong(tester);
    expect(api.streamStarts, 2);
    expect(api.count('/events/snapshot'), 2);
    runtime.realtime.release();
  });
  testWidgets('HTTP snapshot cannot roll back a state that arrived over SSE',
      (tester) async {
    final api = SangongTestApi();
    final gate = Completer<dynamic>();
    api.respond = (_) => gate.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    runtime.realtime.acquire();
    await flushSangong(tester);
    api.streams.last
        .add('event: state\ndata: ${jsonEncode(sangongState(8))}\n\n');
    await tester.pump();
    gate.complete(sangongState(2));
    await flushSangong(tester);
    expect(runtime.realtime.latestState!.version, 8);
    runtime.realtime.release();
  });
  testWidgets(
      'disposing a live scope cancels stream and prevents delayed snapshot application',
      (tester) async {
    final api = SangongTestApi();
    final gate = Completer<dynamic>();
    api.respond = (_) => gate.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    runtime.realtime.acquire();
    await flushSangong(tester);
    runtime.dispose();
    gate.complete(sangongState(9));
    await flushSangong(tester);
    expect(api.streamStops, 1);
    expect(runtime.realtime.latestState, isNull);
    expect(runtime.isCurrent, isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'empty HTTP snapshot is an error rather than a normal six-door state',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    runtime.realtime.acquire();
    await flushSangong(tester);
    expect(runtime.realtime.latestState, isNull);
    expect(runtime.realtime.error, '返回数据格式无效，请重试');
    expect(api.count('/events/snapshot'), 1);
    runtime.realtime.release();
  });
  testWidgets(
      'missing or zero SSE version calibrates and does not freeze future state',
      (tester) async {
    final api = SangongTestApi();
    var snapshotVersion = 1;
    api.respond = (_) => sangongState(snapshotVersion++);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    runtime.realtime.acquire();
    await flushSangong(tester);
    final missing = sangongState(2)..remove('version');
    api.streams.last.add('event: state\ndata: ${jsonEncode(missing)}\n\n');
    await flushSangong(tester);
    expect(api.count('/events/snapshot'), 2);
    expect(runtime.realtime.latestState!.version, 2);
    api.streams.last
        .add('event: state\ndata: ${jsonEncode(sangongState(0))}\n\n');
    await flushSangong(tester);
    expect(api.count('/events/snapshot'), 3);
    expect(runtime.realtime.latestState!.version, 3);
    api.streams.last
        .add('event: state\ndata: ${jsonEncode(sangongState(4))}\n\n');
    await tester.pump();
    expect(runtime.realtime.latestState!.version, 4);
    expect(runtime.realtime.error, isNull);
    runtime.realtime.release();
  });
}
