import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_game_settings.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_game_rules_settings_page.dart';
import 'package:openim/pages/group_features/sangong/support/settings_exports.dart';
import '../sangong_test_support.dart';

void main() {
  testWidgets('save accepts every count 2–9 and rejects 10 without a request',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    api.respond = (call) => {
          'ok': true,
          'requestId': call.body!['requestId'],
          'data': call.body!['input']
        };
    for (var count = 2; count <= 9; count++) {
      final rules = SangongGameSettings.defaults().copyWith(doorCount: count);
      final saved =
          await completeSangongRequest(tester, runtime.settings.save(rules));
      expect(saved.doorCount, count);
      expect(api.calls.last.body!['input']['doorCount'], count);
    }
    final legacy = SangongGameSettings.fromJson(
        {'doorCount': 10, 'minBet': 0, 'maxBet': 0, 'rakePercent': 6});
    expect(legacy.doorCount, 10);
    expect(legacy.isValid, isTrue);
    final before = api.calls.length;
    await rejectSangongRequest(
        tester, runtime.settings.save(legacy), isArgumentError);
    expect(api.calls.length, before);
  });

  for (final dark in [false, true]) {
    testWidgets('choose 9 packets from all eight choices and save; dark=$dark',
        (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = SangongTestApi();
      final runtime = sangongTestRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      api.respond = (call) {
        if (call.path.endsWith('/snapshot')) {
          return {
            'ok': true,
            'data': {
              ...sangongState(1),
              'round': {
                'id': 18,
                'sessionId': 2,
                'periodNo': 3,
                'status': 'await_banker'
              }
            }
          };
        }
        if (call.path.endsWith('/commands/rules.update')) {
          return {
            'ok': true,
            'requestId': call.body!['requestId'],
            'data': call.body!['input']
          };
        }
        return sangongFixtureResponse(call);
      };
      await pumpSangongPage(
          tester, runtime, const SangongGameRulesSettingsPage(),
          dark: dark);
      final cell = find.byKey(const ValueKey('sangong-draw-count'));
      await tester.scrollUntilVisible(cell, 300,
          scrollable: find.byType(Scrollable).first);
      expect(tester.getSize(cell).height, greaterThanOrEqualTo(48));
      await tester.tap(cell);
      await tester.pumpAndSettle();
      for (var count = 2; count <= 9; count++) {
        expect(find.widgetWithText(CupertinoActionSheetAction, '$count 包'),
            findsOneWidget);
      }
      expect(find.text('10 包'), findsNothing);
      final nine = find.widgetWithText(CupertinoActionSheetAction, '9 包');
      await tester.ensureVisible(nine);
      await tester.tap(nine);
      await tester.pumpAndSettle();
      expect(tester.widget<SettingsCell>(cell).value, '9 包');
      expect(api.count('/commands/rules.update'), 0);
      await tester.tap(find.text('保存'));
      await flushSangong(tester);
      final write = api.calls
          .singleWhere((call) => call.path.endsWith('/commands/rules.update'));
      expect(write.body!['input']['doorCount'], 9);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'existing ten-packet round stays visible and cannot be changed after banker selection',
      (tester) async {
    final api = SangongTestApi();
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    api.respond = (call) => call.path.endsWith('/snapshot')
        ? {
            'ok': true,
            'data': {
              ...sangongState(1),
              'settings': SangongGameSettings.defaults()
                  .copyWith(doorCount: 10)
                  .toJson()
            }
          }
        : sangongFixtureResponse(call);
    await pumpSangongPage(
        tester, runtime, const SangongGameRulesSettingsPage());
    final cell = find.byKey(const ValueKey('sangong-draw-count'));
    await tester.scrollUntilVisible(cell, 300,
        scrollable: find.byType(Scrollable).first);
    expect(tester.widget<SettingsCell>(cell).value, '10 包');
    expect(tester.widget<SettingsCell>(cell).onTap, isNull);
    expect(tester.takeException(), isNull);
  });
}
