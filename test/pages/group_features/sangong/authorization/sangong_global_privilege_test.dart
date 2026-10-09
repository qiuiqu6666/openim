import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/data/group_feature_store.dart';
import 'package:openim/pages/group_features/models/group_game_type.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_my_config.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_surface.dart';
import 'package:openim/pages/group_features/sangong/profile/sangong_profile_panel.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_agent_floating_entry.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';
import '../sangong_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OpenIM.iMManager.userID = 'owner';
  });

  testWidgets(
      'unassigned ordinary user cannot call private APIs despite management flags',
      (tester) async {
    final api = SangongTestApi()..privilege.setAllowed(false);
    final runtime =
        SangongRuntime(sangongTestContext(api, canOpenAgent: false));
    addTearDown(runtime.dispose);
    expect(runtime.canConfigure, isFalse);
    expect(runtime.canManage, isFalse);
    expect(runtime.canOpenAgent, isFalse);
    expect(runtime.canViewRebateHistory, isFalse);
    expect(runtime.http.hasTenant, isFalse);
    for (final request in <Future<dynamic> Function()>[
      runtime.admin.fetchMyConfig,
      runtime.admin.fetchSession,
      runtime.settings.fetch,
      () => runtime.agent.fetchEntryContext('group-sangong'),
      () => runtime.agent.fetchSangongMemberDaily(imUserId: 'owner'),
    ]) {
      await rejectSangongRequest(tester, request(), isA<DioException>());
    }
    expect(api.calls, isEmpty);
  });

  testWidgets(
      'true global privilege still requires current business capabilities',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false,
        canViewHistory: false));
    addTearDown(runtime.dispose);
    expect(runtime.isPrivileged, isTrue);
    expect(runtime.canConfigure, isFalse);
    expect(runtime.canManage, isFalse);
    expect(runtime.canOpenAgent, isFalse);
    await rejectSangongRequest(
        tester, runtime.admin.fetchMyConfig(), isA<DioException>());
    await rejectSangongRequest(tester,
        runtime.agent.fetchEntryContext('group-sangong'), isA<DioException>());
    expect(api.calls, isEmpty);
  });

  testWidgets('revocation clears bindings and cached configuration immediately',
      (tester) async {
    final api = SangongTestApi();
    final runtime =
        SangongRuntime(sangongTestContext(api, canOpenAgent: false));
    addTearDown(runtime.dispose);
    await runtime.config.applySaved(SangongMyConfig.fromJson(sangongConfig()));
    var notifications = 0;
    runtime.addListener(() => notifications++);
    api.privilege.setAllowed(false);
    expect(runtime.config.hasCachedConfig, isFalse);
    expect(runtime.http.tenantId, isNull);
    expect(runtime.agentContext, isNull);
    expect(runtime.canManageMembers, isFalse);
    expect(notifications, greaterThan(0));
  });

  testWidgets('regrant cannot accept an old in-flight response',
      (tester) async {
    final response = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => response.future;
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final request = runtime.admin.fetchSession();
    final rejection = expectLater(request, throwsA(isA<DioException>()));
    await flushSangong(tester);
    expect(api.count('/snapshot'), 1);
    api.privilege.setAllowed(false);
    api.privilege.setAllowed(true);
    response.complete({'status': 'running', 'round': null});
    await flushSangong(tester);
    await rejection;
    expect(runtime.canManage, isFalse);
    expect(runtime.groupTenant.state, isNull);
  });

  testWidgets(
      'new grant starts a fresh config read and cannot turn the old failure into cached success',
      (tester) async {
    final oldResponse = Completer<dynamic>();
    final api = SangongTestApi();
    api.respond = (call) => api.count('/config') == 1
        ? oldResponse.future
        : sangongFixtureResponse(call);
    final runtime = SangongRuntime(sangongTestContext(api, tenantID: ''));
    addTearDown(runtime.dispose);
    final oldRead = runtime.config.refreshFromNetwork();
    final rejection = expectLater(oldRead, throwsA(isA<DioException>()));
    await flushSangong(tester);
    api.privilege.setAllowed(false);
    api.privilege.setAllowed(true);
    await completeSangongRequest(tester, runtime.config.refreshFromNetwork());
    expect(api.count('/config'), 2);
    expect(runtime.config.hasCachedConfig, isTrue);
    oldResponse.complete(sangongConfig(name: '撤权前旧厅'));
    await flushSangong(tester);
    await rejection;
    expect(runtime.config.config.name, '一号厅');
  });

  testWidgets(
      'host waits for true privilege then loads a real existing binding once',
      (tester) async {
    final api = SangongTestApi()..privilege.setAllowed(false);
    final feature = sangongTestContext(api, tenantID: '', canOpenAgent: false);
    final outer = SangongRuntime(feature);
    addTearDown(outer.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, outer,
        Scaffold(body: SangongFeatureHost(featureContext: feature)));
    expect(api.calls, isEmpty);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    api.privilege.setAllowed(true);
    await flushSangong(tester);
    await flushSangong(tester);
    expect(api.count('/config'), 1);
    expect(api.count('/my-config'), 0);
    expect(find.byType(GroupGameFloatingEntry), findsOneWidget);
    expect(
        tester
            .widget<GroupGameFloatingEntry>(find.byType(GroupGameFloatingEntry))
            .setupOnly,
        isFalse);
    api.privilege.setAllowed(false);
    await flushSangong(tester);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(find.byType(SangongAgentFloatingEntry), findsNothing);
    final calls = api.calls.length;
    await tester.pump(const Duration(seconds: 2));
    expect(api.calls.length, calls);
    expect(tester.takeException(), isNull);
  });

  testWidgets('module entry refreshes before constructing any denied page',
      (tester) async {
    final api = SangongTestApi()..privilege.setAllowed(false);
    final feature = sangongTestContext(api);
    final runtime = SangongRuntime(feature);
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => unawaited(SangongModule.openManage(context,
                        featureContext: feature)),
                    child: const Text('普通聊天')))));
    await tester.tap(find.text('普通聊天'));
    await flushSangong(tester);
    expect(api.privilege.refreshCount, 1);
    expect(api.calls, isEmpty);
    expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
    expect(find.text('普通聊天'), findsOneWidget);
  });

  testWidgets(
      'toolbox removes management while retaining an assigned agent entry',
      (tester) async {
    final api = SangongTestApi();
    final feature =
        sangongTestContext(api, gameType: GroupGameType.sangongAgent);
    final runtime = SangongRuntime(feature);
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const Scaffold(body: Text('聊天')));
    final context = tester.element(find.text('聊天'));
    expect(GroupFeatureActions.items(context, feature).map((i) => i.text),
        containsAll(['三公运营', '三公代理']));
    api.privilege.setAllowed(false);
    final hidden =
        GroupFeatureActions.items(context, feature).map((i) => i.text).toList();
    expect(hidden, isNot(contains('三公运营')));
    expect(hidden, contains('三公代理'));
    expect(hidden, contains('群直播'));
  });

  testWidgets(
      'ordinary profile stays usable while true grant discovers and false clears game entry',
      (tester) async {
    final api = SangongTestApi()..privilege.setAllowed(false);
    api.respond = (call) {
      if (call.path.endsWith('/feature-capabilities')) {
        return {
          'groupID': 'g',
          'capabilityVersion': 1,
          'sangong': {'canManage': true, 'tenantID': 'tenant-authorized'}
        };
      }
      if (call.path.endsWith('/user')) {
        return {
          'exists': true,
          'user': {'userId': 19, 'imUserId': 'target', 'balance': 420},
          'parent': {'nickname': '上级甲'}
        };
      }
      return sangongFixtureResponse(call);
    };
    final group = GroupInfo.fromJson({
      'groupID': 'g',
      'groupName': '游戏群',
      'ex': jsonEncode({
        'groupFeatures': {
          'schemaVersion': 1,
          'revision': 1,
          'games': {
            'sangong': {'enabled': true, 'manageEntry': true}
          }
        }
      })
    });
    final store = GroupFeatureStore(
        api: api,
        accountPrivilege: api.privilege,
        sessionCurrent: () => true,
        fetchGroups: (_) async => [group]);
    addTearDown(store.dispose);
    addTearDown(() => unmountSangong(tester));
    var inventories = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SangongProfileSurface(
                userID: 'target',
                store: store,
                loadGroups: () async {
                  inventories++;
                  return [group];
                },
                child: const SingleChildScrollView(
                    child: Column(children: [
                  Text('普通资料'),
                  SangongInlineProfilePanel(userID: 'target')
                ]))))));
    await flushSangong(tester);
    expect(inventories, 0);
    expect(api.calls, isEmpty);
    expect(find.text('普通资料'), findsOneWidget);
    api.privilege.setAllowed(true);
    await flushSangong(tester);
    await flushSangong(tester);
    expect(inventories, 1);
    expect(find.textContaining('当前积分 420'), findsOneWidget);
    expect(api.privilege.refreshCount, 1);
    api.privilege.setAllowed(false);
    await tester.pump();
    expect(find.textContaining('当前积分 420', skipOffstage: false), findsNothing);
    expect(find.text('流水'), findsNothing);
    expect(find.text('普通资料'), findsOneWidget);
    expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse);
    expect(tester.takeException(), isNull);
  });
}
