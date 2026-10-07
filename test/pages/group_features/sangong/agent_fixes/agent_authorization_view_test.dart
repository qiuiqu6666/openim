import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_team_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import 'package:openim/pages/group_features/sangong/widgets/authorization/sangong_agent_authorized_view.dart';
import '../sangong_test_support.dart';

void main() {
  for (final page in ['dashboard', 'team']) {
    for (final change in ['tenant', 'capabilities']) {
      testWidgets(
          '$page hides loaded private data when $change changes with access intact',
          (tester) async {
        final api = SangongTestApi()
          ..respond = (_) => {
                'summary': <String, dynamic>{},
                'version': 1,
                'nextBeforeId': 0,
                'members': [
                  {
                    'imUserId': 'winter',
                    'nickname': '受保护的团队用户',
                    'balance': 123,
                  }
                ],
              };
        final runtime = SangongRuntime(sangongTestContext(api));
        addTearDown(runtime.dispose);
        addTearDown(() => unmountSangong(tester));
        await pumpSangongPage(
            tester,
            runtime,
            page == 'dashboard'
                ? const SangongAgentDashboardPage()
                : const SangongAgentTeamPage());
        if (page == 'dashboard') {
          await tester.scrollUntilVisible(find.text('受保护的团队用户'), 200,
              scrollable: find.byType(Scrollable).first);
        }
        expect(find.text('受保护的团队用户'), findsOneWidget);
        if (change == 'tenant') {
          runtime.http.setTenantId('tenant-other');
        } else {
          runtime.updateContext(sangongTestContext(api, capabilityVersion: 2));
        }
        expect(runtime.canOpenAgent, isTrue);
        await flushSangong(tester);
        expect(find.text('受保护的团队用户'), findsNothing);
        expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
        expect(api.calls, hasLength(1),
            reason:
                'An expired page must not restart requests in a new scope.');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'history-only content hides when its private capability is revoked',
      (tester) async {
    final api = SangongTestApi();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        SangongAgentAuthorizedView(
          runtime: runtime,
          session: AgentSessionSnapshot(runtime),
          requireHistory: true,
          child: const Scaffold(body: Text('受保护的历史记录')),
        ));
    expect(find.text('受保护的历史记录'), findsOneWidget);
    runtime.updateContext(
        sangongTestContext(api, canViewHistory: false, capabilityVersion: 2));
    expect(runtime.canOpenAgent, isTrue);
    await flushSangong(tester);
    expect(find.text('受保护的历史记录'), findsNothing);
    expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('runtime teardown removes private content before widget teardown',
      (tester) async {
    final runtime = SangongRuntime(sangongTestContext(SangongTestApi()));
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        SangongAgentAuthorizedView(
          runtime: runtime,
          session: AgentSessionSnapshot(runtime),
          child: const Scaffold(body: Text('即将失效的代理数据')),
        ));
    runtime.dispose();
    await flushSangong(tester);
    expect(find.text('即将失效的代理数据'), findsNothing);
    expect(find.text('当前游戏权限已变化，请重新进入'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
