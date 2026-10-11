import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/agents/data/sangong_agent_management_api.dart';
import 'package:openim/pages/group_features/sangong/agents/pages/sangong_agent_groups_page.dart';
import 'package:openim/pages/group_features/sangong/agents/widgets/sangong_agent_user_actions.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import '../sangong_test_support.dart';

void main() {
  test('percent input preserves all four decimals without binary arithmetic',
      () {
    expect(sangongRebateRate('2.1234'), '2.1234');
    expect(sangongRebateRate('0'), '0.0000');
    expect(sangongRebateRate('100.0000'), '100.0000');
    for (final value in ['-1', '100.0001', '1e2', '1.23456', 'NaN']) {
      expect(() => sangongRebateRate(value), throwsStateError);
    }
  });
  testWidgets('binding and rates use current group and confirmed v2 receipts',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final management = SangongAgentManagementApi(runtime.http);
    api.respond = (call) => call.method == 'GET'
        ? {
            'gameGroupId': runtime.featureContext.groupID,
            'agentGroupIds': ['agent-room']
          }
        : {
            'ok': true,
            'requestId': call.body!['requestId'],
            'data': {
              ...(call.body!['input'] as Map<String, dynamic>),
              'gameGroupId': runtime.featureContext.groupID,
              'tenantId': runtime.http.tenantId
            }
          };
    expect(await completeSangongRequest(tester, management.groups()),
        ['agent-room']);
    await completeSangongRequest(tester, management.bind('new-agent'));
    await completeSangongRequest(tester, management.attach(42, 7));
    await completeSangongRequest(tester, management.setRate(42, '2.1234'));
    expect(api.calls.last.path,
        '/sangong/api/v2/groups/group-sangong/commands/admin.rebate_rate');
    expect(api.calls.last.body!['input'], {'userId': 42, 'rate': '2.1234'});
    await completeSangongRequest(tester,
        SangongAgentManagementApi(runtime.http, agent: true).setRate(42, '1'));
    expect(api.calls.last.path,
        '/sangong/api/v2/agent-groups/group-sangong/commands/agent.rate');
    expect(api.calls.every((c) => c.useBearerAuth), isTrue);
    expect(api.calls.last.body!['expectedTenantId'], runtime.http.tenantId);
    expect(api.calls.last.body!['tenantId'], runtime.http.tenantId);
    api.respond = (_) => {
          'gameGroupId': 'other',
          'agentGroupIds': ['secret-group']
        };
    await rejectSangongRequest(
        tester, management.groups(), isA<FormatException>());
  });

  for (final parent in [0, 7]) {
    testWidgets('admin can set or replace parent ($parent)', (tester) async {
      final runtime = sangongTestRuntime(sangongTestContext(SangongTestApi()));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(
          tester,
          runtime,
          Scaffold(
              body: SangongAgentUserActions(
                  userId: 42,
                  imUserId: 'child',
                  nickname: '成员',
                  rebatePct: 1,
                  parentUserId: parent,
                  onChanged: () async {})));
      expect(find.text(parent == 0 ? '设置上级' : '修改上级'), findsOneWidget);
      await tester.tap(find.text(parent == 0 ? '设置上级' : '修改上级'));
      await flushSangong(tester);
      expect(find.textContaining('上级须属于当前下注群'), findsOneWidget);
      expect(find.textContaining('已有账务或下级'), findsNothing);
    });
  }

  testWidgets(
      'attach pins tenant, reuses uncertain request and refreshes only after confirmation',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    final management = SangongAgentManagementApi(runtime.http);
    api.respond = (_) => throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.receiveTimeout);
    await rejectSangongRequest(
        tester, management.attach(42, 7), isA<DioException>());
    final first = Map<String, dynamic>.from(api.calls.single.body!);
    expect(first['expectedTenantId'], runtime.http.tenantId);
    expect(first.containsKey('tenantId'), isFalse);
    expect(runtime.http.agentDataRevision.value, 0);
    api.respond = (call) => {
          'ok': true,
          'requestId': call.body!['requestId'],
          'data': call.body!['input']
        };
    await completeSangongRequest(tester, management.attach(42, 7));
    expect(api.calls.last.body, first);
    expect(runtime.http.agentDataRevision.value, 1);
    await completeSangongRequest(tester, management.attach(42, 8));
    expect(api.calls.last.body!['requestId'], isNot(first['requestId']));
    expect(api.calls.last.body!['input'], {'userId': 42, 'parentUserId': 8});
    final before = api.calls.length;
    await rejectSangongRequest(
        tester,
        SangongAgentManagementApi(runtime.http, agent: true).attach(42, 9),
        isA<StateError>());
    expect(api.calls.length, before);
  });

  testWidgets('confirmed rate reloads mounted team and pending rebate summary',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.method == 'POST'
          ? {
              'ok': true,
              'requestId': call.body!['requestId'],
              'data': call.body!['input']
            }
          : sangongFixtureResponse(call);
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentDashboardPage());
    final before = api.count('/team-summary');
    expect(before, 1);
    await completeSangongRequest(
        tester, SangongAgentManagementApi(runtime.http).setRate(42, '2.5'));
    await flushSangong(tester);
    expect(api.count('/team-summary'), before + 1);
    expect(api.calls.where((c) => c.method == 'POST').map((c) => c.path),
        ['/sangong/api/v2/groups/group-sangong/commands/admin.rebate_rate']);
    await unmountSangong(tester);
    runtime.http.agentDataChanged();
    await flushSangong(tester);
    expect(api.count('/team-summary'), before + 1);
    expect(tester.takeException(), isNull);
  });

  for (final code in [
    'HIERARCHY_LOCKED',
    'INVALID_PARENT',
    'MEMBER_NOT_FOUND',
    'RATE_EXCEEDS_PARENT',
    'RATE_BELOW_CHILD',
    'REBATE_HISTORY_INCOMPLETE'
  ]) {
    testWidgets('$code never retries or pays rebates', (tester) async {
      final api = SangongTestApi()
        ..respond = (_) => {'ok': false, 'code': code, 'message': code};
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      await rejectSangongRequest(
          tester,
          SangongAgentManagementApi(runtime.http).setRate(42, '0'),
          isA<DioException>());
      await flushSangong(tester);
      expect(api.calls, hasLength(1));
      expect(api.calls.single.body!['input'], {'userId': 42, 'rate': '0.0000'});
      expect(runtime.http.agentDataRevision.value, 0);
    });
  }

  for (final dark in [false, true]) {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      testWidgets('binding page stays scoped ($dark, $platform)',
          (tester) async {
        final api = SangongTestApi()
          ..respond = (_) => {
                'gameGroupId': 'group-sangong',
                'agentGroupIds': ['bound-agent-room']
              };
        final runtime = sangongTestRuntime(sangongTestContext(api));
        addTearDown(runtime.dispose);
        addTearDown(() => unmountSangong(tester));
        await pumpSangongPage(tester, runtime, const SangongAgentGroupsPage(),
            dark: dark, platform: platform);
        expect(find.text('bound-agent-room'), findsOneWidget);
        expect(api.calls, hasLength(1));
        runtime.http.setTenantId('other-tenant');
        await flushSangong(tester);
        expect(find.text('bound-agent-room'), findsNothing);
        expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
        expect(api.calls, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('late binding response cannot expose another session data',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    final api = SangongTestApi()..respond = (_) => response.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentGroupsPage());
    runtime.http.setTenantId('other-tenant');
    response.complete({
      'gameGroupId': 'group-sangong',
      'agentGroupIds': ['late-private-group']
    });
    await flushSangong(tester);
    expect(find.text('late-private-group'), findsNothing);
    expect(api.calls, hasLength(1));
    expect(tester.takeException(), isNull);
  });
  for (final parent in [7, 8]) {
    testWidgets('agent can change only direct child rates (parent $parent)',
        (tester) async {
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      runtime.agentContext =
          const AgentEntryContextDto(showAgentEntry: true, userId: '7');
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(
          tester,
          runtime,
          Scaffold(
              body: SangongAgentUserActions(
                  userId: 42,
                  imUserId: 'child',
                  nickname: '下级',
                  rebatePct: 1,
                  parentUserId: parent,
                  agent: true,
                  onChanged: () async {})));
      expect(find.text('设置返水'), parent == 7 ? findsOneWidget : findsNothing);
      expect(find.text('设置上级'), findsNothing);
      runtime.http.setTenantId('other-tenant');
      await flushSangong(tester);
      expect(find.text('设置返水'), findsNothing);
      expect(api.calls, isEmpty);
    });
  }
}
