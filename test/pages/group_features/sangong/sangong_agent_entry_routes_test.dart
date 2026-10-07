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
        await tester.tap(find.byTooltip('展开代理功能'));
        await flushSangong(tester);
        await tester.pump(const Duration(milliseconds: 400));

        await tester.tap(find.byTooltip(entry.tooltip));
        await flushSangong(tester);
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text(entry.title), findsOneWidget);
        expect(api.count(entry.endpoint), 1);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
