import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/data/group_feature_api.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/widgets/group_game_floating_entry.dart';
import 'sangong_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  for (final dark in [false, true]) {
    testWidgets('first configuration is the reference input page, dark=$dark',
        (tester) async {
      final api = SangongTestApi()..respond = (_) => {'configured': false};
      final runtime = SangongRuntime(sangongTestContext(api,
          enabled: false, canManage: false, canOpenAgent: false, tenantID: ''));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(tester, runtime,
          const SangongMyConfigPage(initialGameGroupId: 'group-sangong'),
          dark: dark);
      expect(find.text('我的配置'), findsOneWidget);
      expect(find.text('厅名'), findsOneWidget);
      expect(find.text('下注群'), findsOneWidget);
      expect(find.text('机器人'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(5));
      final fields =
          tester.widgetList<TextField>(find.byType(TextField)).toList();
      expect(fields[1].controller!.text, 'group-sangong');
      expect(fields.every((field) => !field.readOnly), isTrue);
      expect(api.count('/config'), 1);
      final tenant = expectedSangongRequestTenant(skipTenant: true);
      expect(
          api.calls.single.headers?.containsKey('X-Tenant-Id'), tenant != null);
      expect(api.calls.single.headers?['X-Tenant-Id'], tenant);
      expect(api.calls.single.useBearerAuth, isTrue);
      expect(tester.takeException(), isNull);
    });
    testWidgets('service error is visible with retry, dark=$dark',
        (tester) async {
      final api = SangongTestApi()
        ..respond = (_) => throw const GroupFeatureException('该功能的服务暂未开通',
            code: 'SERVICE_UNAVAILABLE', unavailable: true);
      final runtime = SangongRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(tester, runtime, const SangongMyConfigPage(),
          dark: dark);
      expect(find.text('该功能的服务暂未开通'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('保存'), findsNothing);
      api.respond = (_) => {'configured': false};
      await tester.tap(find.text('重试'));
      await flushSangong(tester);
      expect(api.count('/config'), 2);
      expect(find.text('保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
      'current-group management preserves rules, config and users without default members',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        const SangongManageHomePage(
            gameGroupId: 'group-sangong',
            canEditConfig: true,
            canManageMembers: true));
    for (final title in ['三公管理', '游戏规则', '我的配置', '全部用户']) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('成员管理'), findsNothing);
    await tester.tap(find.text('游戏规则'));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SangongGameRulesSettingsPage), findsOneWidget);
    expect(api.count('/snapshot'), 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets('private agent page renders real failure and can retry',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) =>
          throw const GroupFeatureException('你没有该功能的操作权限', code: 'FORBIDDEN');
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentDashboardPage());
    expect(find.text('你没有该功能的操作权限'), findsOneWidget);
    expect(find.text('团队概览'), findsNothing);
    api.respond = sangongFixtureResponse;
    await tester.tap(find.text('重试'));
    await flushSangong(tester);
    expect(find.text('团队概览'), findsOneWidget);
    expect(api.count('/team-summary'), 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'private daily history has neither an entry nor a request without authorization',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'member': {'imUserId': 'owner', 'nickname': '冬', 'levelNo': 1}
          };
    final runtime =
        SangongRuntime(sangongTestContext(api, canViewHistory: false));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        SangongAgentMemberDetailPage(
            member: SangongTeamMemberDto.fromJson(
                {'imUserId': 'owner', 'nickname': '冬'})));
    expect(find.text('个人最新数据'), findsOneWidget);
    expect(find.text('个人每天数据'), findsNothing);
    expect(find.text('划转记录'), findsNothing);
    expect(api.count('/member-daily'), 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'host reacts to late capabilities, respects event key and revocation',
      (tester) async {
    final api = SangongTestApi();
    final events = StreamController<Map<String, dynamic>>.broadcast();
    final state = ValueNotifier<GroupFeatureContext>(sangongTestContext(api,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false,
        tenantID: '',
        events: events.stream));
    final outer = SangongRuntime(state.value);
    addTearDown(outer.dispose);
    addTearDown(state.dispose);
    addTearDown(events.close);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        outer,
        Scaffold(
            body: ValueListenableBuilder<GroupFeatureContext>(
                valueListenable: state,
                builder: (_, context, __) =>
                    SangongFeatureHost(featureContext: context))));
    expect(api.count('/config'), 1);
    expect(api.count('/snapshot'), 0);
    state.value = sangongTestContext(api,
        canConfigure: false,
        canOpenAgent: false,
        tenantID: '',
        capabilityVersion: 2,
        events: events.stream);
    await flushSangong(tester);
    expect(api.count('/config'), 2);
    expect(api.streamStarts, 0);
    expect(find.byType(GroupGameFloatingEntry), findsOneWidget);
    events.add(
        {'key': 'groupGameChanged', 'groupID': 'group-sangong', 'action': ''});
    await flushSangong(tester);
    expect(api.count('/snapshot'), 1);
    state.value = sangongTestContext(api,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false,
        tenantID: '',
        capabilityVersion: 3,
        events: events.stream);
    await flushSangong(tester);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(api.streamStops, 0);
    final callsAfterRevocation = api.calls.length;
    events.add({'key': 'groupGameChanged', 'groupID': 'group-sangong'});
    await flushSangong(tester);
    expect(api.calls.length, callsAfterRevocation);
    api.privilege.setAllowed(false);
    await flushSangong(tester);
    expect(find.byType(GroupGameFloatingEntry), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'eight native operator controls stay within a small chat body and scroll',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = SangongTestApi();
    final context = sangongTestContext(api,
        groupID: 'small-control-group', canOpenAgent: false);
    final runtime = SangongRuntime(context);
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        Scaffold(
            body: Center(
                child: SizedBox(
                    width: 320,
                    height: 360,
                    child: SangongFeatureHost(featureContext: context)))));
    await tester.tap(find.byTooltip('展开游戏功能'));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 400));
    final panel = find.descendant(
        of: find.byType(GroupGameFloatingEntry),
        matching: find.byType(SingleChildScrollView));
    expect(panel, findsOneWidget);
    expect(tester.getSize(panel).height, lessThanOrEqualTo(344));
    await tester.drag(panel, const Offset(0, -320));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('收起').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'host retry recovers the failed snapshot without starting SSE',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/snapshot')) {
          throw const GroupFeatureException('快照暂时无法读取', code: 'NETWORK_ERROR');
        }
        return sangongFixtureResponse(call);
      };
    final context = sangongTestContext(api, canOpenAgent: false);
    final runtime = SangongRuntime(context);
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime,
        Scaffold(body: SangongFeatureHost(featureContext: context)));
    expect(find.text('快照暂时无法读取'), findsOneWidget);
    expect(api.count('/snapshot'), 1);
    expect(api.streamStarts, 0);
    api.respond = sangongFixtureResponse;
    await tester.tap(find.byKey(const ValueKey('sangong-host-retry')));
    await flushSangong(tester);
    expect(api.count('/snapshot'), 2);
    expect(api.streamStarts, 0);
    expect(find.text('快照暂时无法读取'), findsNothing);
    expect(find.byKey(const ValueKey('sangong-status-banner')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
