import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_transfers_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('transfer filters and empty state dark=$dark', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SangongTestApi()
        ..respond = (_) => {'transfers': [], 'nextBeforeId': 0};
      final runtime = SangongRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(tester, runtime, const SangongAgentTransfersPage(),
          dark: dark);
      expect(find.text('暂无划转记录'), findsOneWidget);
      await tester.tap(find.text('转出'));
      await flushSangong(tester);
      expect(api.calls.last.query?['direction'], 'out');
      await tester.enterText(find.byType(TextField), '12');
      await tester.tap(find.text('查询'));
      await flushSangong(tester);
      expect(api.calls.last.query?['sessionId'], 12);
      expect(find.text('查看全部批次'), findsOneWidget);
      await tester.tap(find.text('查看全部批次'));
      await flushSangong(tester);
      expect(api.calls.last.query?.containsKey('sessionId'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
