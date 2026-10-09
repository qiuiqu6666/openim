import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/contacts/group_list/group_list_logic.dart';
import 'package:openim/pages/contacts/group_list/group_list_view.dart';
import 'package:openim/pages/group_features/models/group_game_type.dart';
import 'package:openim/pages/group_features/sangong/agents/user_group/sangong_user_agent_group_entry.dart';
import 'package:openim/pages/group_features/sangong/api/sangong_v2_api.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:openim/pages/group_features/widgets/group_feature_actions.dart';
import '../../sangong_test_support.dart';

void main() {
  testWidgets(
      'assigned ordinary user sees own agent entry and cannot use management',
      (tester) async {
    final api = SangongTestApi()..privilege.setAllowed(false);
    final context = sangongTestContext(api,
        gameType: GroupGameType.sangongAgent,
        canConfigure: false,
        canManage: false,
        manageEntry: false);
    final runtime = sangongTestRuntime(context);
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    expect(runtime.canOpenAgent, isTrue);
    expect(runtime.canManage, isFalse);
    expect(runtime.http.canCallAdmin, isFalse);
    await pumpSangongPage(tester, runtime, const Scaffold(body: Text('群聊')));
    final pageContext = tester.element(find.text('群聊'));
    final actions = GroupFeatureActions.items(pageContext, context)
        .map((item) => item.text);
    expect(actions, contains('三公代理'));
    expect(actions, isNot(contains('三公运营')));
    final agent = SangongV2Api(runtime.http, agent: true);
    await completeSangongRequest(tester, agent.read('context'));
    await rejectSangongRequest(
        tester, SangongV2Api(runtime.http).read('users'), isA<DioException>());
    unawaited(SangongAgentDashboardPage.open(pageContext));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SangongAgentDashboardPage), findsOneWidget);
    expect(api.calls.where((c) => c.path.contains('/api/v2/agent-groups/')),
        isNotEmpty);
    expect(api.calls.where((c) => c.path.contains('/api/v2/groups/')), isEmpty);
    runtime.updateContext(sangongTestContext(api,
        gameType: GroupGameType.sangongAgent,
        canConfigure: false,
        canManage: false,
        canOpenAgent: false,
        canViewHistory: false,
        capabilityVersion: 2));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(SangongAgentDashboardPage), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'direct group picker allows previously unbound groups dark=$dark',
        (tester) async {
      final runtime = sangongTestRuntime(sangongTestContext(SangongTestApi()));
      final logic = GroupListLogic(
          currentUserID: () => 'owner',
          fetchPage: (_, __) async => [
                GroupInfo(
                    groupID: 'agents-A',
                    groupName: '可选代理群',
                    ownerUserID: 'owner'),
                GroupInfo(
                    groupID: 'unbound',
                    groupName: '普通群聊',
                    ownerUserID: 'owner'),
              ]);
      GroupInfo? selected;
      logic.onInit();
      addTearDown(logic.onClose);
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(
          tester,
          runtime,
          GroupListPage(
            logic: logic,
            title: '选择代理群',
            onSelected: (group) => selected = group,
          ),
          dark: dark);
      await flushSangong(tester);
      expect(find.text('未绑定当前下注群'), findsNothing);
      await tester.tap(find.text('普通群聊'));
      expect(selected?.groupID, 'unbound');
      await tester.tap(find.text('可选代理群'));
      expect(selected?.groupID, 'agents-A');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'manager assigns and clears a user group with real names dark=$dark',
        (tester) async {
      String? assigned;
      final api = SangongTestApi();
      api.respond = (call) {
        if (call.path.endsWith('/agent-groups')) {
          return {'gameGroupId': 'group-sangong', 'agentGroupIds': <String>[]};
        }
        if (call.method == 'POST') {
          expect(call.path, endsWith('/commands/user.agent_group'));
          final input = call.body!['input'] as Map;
          expect(input['bindIfNeeded'],
              input['agentGroupId'] == '' ? isNull : isTrue);
          assigned = input['agentGroupId'] == ''
              ? null
              : input['agentGroupId'] as String;
          return {
            'ok': true,
            'requestId': call.body!['requestId'],
            'data': {
              'imUserId': 'player',
              'gameGroupId': 'group-sangong',
              'agentGroupId': assigned
            }
          };
        }
        return {
          'imUserId': 'player',
          'gameGroupId': 'group-sangong',
          'agentGroupId': assigned
        };
      };
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(
          tester,
          runtime,
          Scaffold(
              body: SangongUserAgentGroupEntry(
                  imUserId: 'player',
                  hasRebate: true,
                  fetchGroups: (_) async =>
                      [GroupInfo(groupID: 'agents-A', groupName: '秋的代理群')],
                  pickGroup: (_) async {
                    return GroupInfo(groupID: 'agents-A', groupName: '秋的代理群');
                  })),
          dark: dark);
      await flushSangong(tester);
      expect(find.text('未设置'), findsOneWidget);
      await tester.tap(find.text('设置'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('秋的代理群'), findsOneWidget);
      await tester.tap(find.text('确定'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(assigned, 'agents-A');
      expect(find.text('秋的代理群'), findsOneWidget);
      expect(find.text('agents-A'), findsNothing);
      await tester.tap(find.text('清除绑定'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('确定'));
      await flushSangong(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(assigned, isNull);
      expect(api.calls.where((c) => c.path.endsWith('/agent-groups')), isEmpty);
      expect(api.calls.where((c) => c.method == 'POST'), hasLength(2));
      expect(find.text('未设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late assignment query is hidden after group scope changes',
      (tester) async {
    final response = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => response.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        Scaffold(
            body: SangongUserAgentGroupEntry(
                imUserId: 'player',
                hasRebate: true,
                fetchGroups: (_) async =>
                    [GroupInfo(groupID: 'secret', groupName: '旧群私密资料')])));
    runtime.http.setTenantId('other');
    response.complete({
      'imUserId': 'player',
      'gameGroupId': 'group-sangong',
      'agentGroupId': 'secret'
    });
    await flushSangong(tester);
    expect(find.text('旧群私密资料'), findsNothing);
    expect(find.text('设置'), findsNothing);
  });
}
