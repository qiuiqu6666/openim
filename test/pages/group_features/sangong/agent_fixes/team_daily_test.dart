import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('team daily pagination dark=$dark scale=$scale',
          (tester) async {
        tester.view.physicalSize = const Size(375, 812);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = SangongTestApi()
          ..respond = (call) {
            if (call.path.endsWith('/team-daily')) {
              return {
                'scope': 'current_team',
                'nextTo': call.query?['to'] == null ? '2024-01-01' : '',
                'days': [
                  {
                    'businessDate':
                        call.query?['to'] == null ? '2026-10-20' : '2024-01-01',
                    'totalTurnover': 123,
                    'totalBalance': 10
                  }
                ]
              };
            }
            return {
              'summary': {'totalBalance': 100},
              'members': [],
              'version': 1,
              'nextBeforeId': 0
            };
          };
        final runtime = SangongRuntime(sangongTestContext(api));
        addTearDown(runtime.dispose);
        addTearDown(() => unmountSangong(tester));
        await pumpSangongPage(
            tester, runtime, const SangongAgentDashboardPage(),
            dark: dark);
        expect(api.calls.where((c) => c.path.endsWith('/team-daily')), isEmpty);
        await tester.tap(find.text('团队每日'));
        await flushSangong(tester);
        expect(find.text('2026-10-20'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('加载更早日期'), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('加载更早日期'));
        await flushSangong(tester);
        await tester.scrollUntilVisible(find.text('2024-01-01'), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('2024-01-01'), findsOneWidget);
        expect(
            api.calls
                .lastWhere((c) => c.path.endsWith('/team-daily'))
                .query?['to'],
            '2024-01-01');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
