import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_game_rules_settings_page.dart';
import '../sangong_test_support.dart';

void main() {
  testWidgets('rule write contains only the four effective group rules',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    api.respond = (call) => {
          'ok': true,
          'requestId': call.body!['requestId'],
          'data': call.body!['input'],
        };
    final rules = SangongGameSettings.defaults().copyWith(rakePercent: 5);
    final saved =
        await completeSangongRequest(tester, runtime.settings.save(rules));
    expect(saved.rakePercent, 5);
    expect(api.calls.single.path,
        '/sangong/api/v2/groups/group-sangong/commands/rules.update');
    expect(api.calls.single.headers, isEmpty);
    expect(api.calls.single.body!['input'], {
      'doorCount': 6,
      'minBet': 0,
      'maxBet': 99999999,
      'rakePercent': 5,
    });
    expect(
        () => SangongGameSettings.fromJson(
            {'doorCount': 6, 'minBet': 0, 'maxBet': 0}),
        throwsFormatException);
    expect(
        () => SangongGameSettings.fromJson(
            {'doorCount': 6, 'minBet': 0, 'maxBet': 0, 'rakePercent': 101}),
        throwsFormatException);
  });

  for (final dark in [false, true]) {
    testWidgets(
        'rules page shows fixed payout and banker-only rake, dark=$dark',
        (tester) async {
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(
          tester, runtime, const SangongGameRulesSettingsPage(),
          dark: dark);
      expect(find.text('游戏规则'), findsOneWidget);
      expect(find.text('庄家抽水（%）'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(4));
      expect(find.text('赔率'), findsNothing);
      expect(find.text('闲抽水'), findsNothing);
      expect(find.textContaining('输赢按 1:1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('stop request pins the batch the operator confirmed',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    api.respond = (call) => {
          'ok': true,
          'requestId': call.body!['requestId'],
          'data': {
            'session': {'id': 9, 'status': 'idle'}
          }
        };
    await completeSangongRequest(
        tester, runtime.admin.stopSession(sessionId: 9));
    expect(api.calls.single.body!['input'], {'sessionId': 9});
  });
}
