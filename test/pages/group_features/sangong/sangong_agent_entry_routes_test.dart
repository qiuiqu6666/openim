import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/group_features/models/group_game_type.dart';
import 'package:openim/pages/group_features/sangong/sangong_module.dart';
import 'sangong_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final dark in [false, true]) {
    for (final entry in [
      (tooltip: '查下级', title: '查询下级', endpoint: '/team'),
      (tooltip: '团队反水', title: '团队统计', endpoint: '/team-summary'),
    ]) {
      testWidgets('${entry.tooltip} opens ${entry.title}, dark=$dark',
          (tester) async {
        final api = SangongTestApi();
        final feature = sangongTestContext(api,
            groupID: 'agent-route-${entry.endpoint}-$dark',
            gameType: GroupGameType.sangongAgent,
            canConfigure: false,
            canManage: false);
        final runtime = SangongRuntime(feature);
        addTearDown(runtime.dispose);
        addTearDown(() => unmountSangong(tester));
        await pumpSangongPage(tester, runtime,
            Scaffold(body: SangongFeatureHost(featureContext: feature)),
            dark: dark);
        await tester.tap(find.byTooltip(entry.tooltip));
        await flushSangong(tester);
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text(entry.title), findsOneWidget);
        expect(api.count(entry.endpoint), 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('fixed-hall chat entry keeps 查 and 团 in the group hall',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/tenants')) {
          return {
            'agentImUserId': 'owner',
            'agentImGroupId': 'shared-agents',
            'tenants': [
              for (final id in ['b'])
                {'tenantId': id, 'name': '$id 厅', 'imGroupGameId': '$id-game'}
            ]
          };
        }
        if (call.path.endsWith('/context')) {
          return {
            ...sangongFixtureResponse(call) as Map<String, dynamic>,
            'tenantId': 'b'
          };
        }
        return sangongFixtureResponse(call);
      };
    final feature = sangongTestContext(api,
        groupID: 'shared-agents',
        gameType: GroupGameType.sangongAgent,
        canConfigure: false,
        canManage: false,
        tenantID: 'b');
    final runtime = SangongRuntime(feature);
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime,
        Scaffold(body: SangongFeatureHost(featureContext: feature)));
    expect(find.text('查'), findsOneWidget);
    await tester.tap(find.byTooltip('查下级'));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('选择厅'), findsNothing);
    expect(find.text('切换厅'), findsNothing);
    expect(find.text('所属厅：b 厅'), findsOneWidget);
    expect(api.calls.last.query?['tenantId'], 'b');
    Navigator.of(tester.element(find.text('查询下级'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('团队反水'));
    await flushSangong(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('团队统计'), findsOneWidget);
    expect(find.text('所属厅：b 厅'), findsOneWidget);
    expect(api.calls.last.query?['tenantId'], 'b');
    expect(tester.takeException(), isNull);
  });
}
