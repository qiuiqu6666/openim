import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/agent_rebate_models.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_dashboard_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_member_detail_page.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_agent_team_page.dart';
import 'package:openim/pages/group_features/sangong/sangong_scope.dart';
import '../sangong_test_support.dart';

Map<String, dynamic> _member({String id = 'winter'}) => {
      'imUserId': id,
      'nickname': '冬',
      'levelNo': 1,
      'balance': 100,
      'batchRebate': 5,
      'pendingRebate': 7,
      'playerTurnover': 100,
      'bankerTurnover': 50,
    };

Map<String, dynamic> _team() => {
      'agent': {'balance': 100},
      'version': 1,
      'nextBeforeId': 0,
      'members': [_member()],
    };

IconButton _transferButton(WidgetTester tester) =>
    tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '划转积分'));

Future<void> _confirmTransfer(WidgetTester tester) async {
  await tester.enterText(find.byType(CupertinoTextField), '10');
  await tester.tap(find.widgetWithText(CupertinoDialogAction, '下一步'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(CupertinoDialogAction, '确认划转'));
  await flushSangong(tester);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('daily history does not inherit the latest batch filter',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/member')
          ? {
              'member': _member(),
              'batch': {'batchNo': 'latest-batch'}
            }
          : {
              'days': [
                {'businessDate': '2025-01-01', 'balance': 1},
                {'businessDate': '2026-10-20', 'balance': 2},
              ]
            };
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        SangongAgentMemberDetailPage(
            member: SangongTeamMemberDto.fromJson(_member())));
    await tester.tap(find.text('个人每天数据'));
    await flushSangong(tester);
    expect(find.text('2025-01-01'), findsOneWidget);
    expect(find.text('2026-10-20'), findsOneWidget);
    for (final call
        in api.calls.where((c) => c.path.endsWith('/member-daily'))) {
      expect(call.query?.containsKey('batchNo'), isFalse);
      expect(call.query?.containsKey('from'), isFalse);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('summary uses lifetime totals instead of current batch',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'member': {..._member(), 'batchProfitLoss': 11, 'batchUp': 22},
            'lifetime': {
              'aggregation': 'all_time',
              'profitLoss': 9876,
              'playerTurnover': 11111,
              'bankerTurnover': 22222,
              'totalTurnover': 33333,
              'totalUp': 44444,
              'totalDown': 55555,
              'rebate': 66666
            },
          };
    final runtime =
        SangongRuntime(sangongTestContext(api, canViewHistory: false));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        SangongAgentMemberDetailPage(
            member: SangongTeamMemberDto.fromJson(_member())));
    await tester.tap(find.text('汇总'));
    await tester.pump();
    expect(find.text('累计盈亏'), findsOneWidget);
    expect(find.text('9876'), findsOneWidget);
    expect(find.text('33333'), findsOneWidget);
    expect(find.text('44444'), findsOneWidget);
    expect(find.text('本批次盈亏'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    testWidgets('pending rebate uses the pending field, dark=$dark',
        (tester) async {
      final api = SangongTestApi()..respond = (_) => _team();
      final runtime = SangongRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(tester, runtime, const SangongAgentTeamPage(),
          dark: dark);
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == '未返水 7'),
          findsOneWidget);
      expect(
          find.byWidgetPredicate(
              (w) => w is Semantics && w.properties.label == '未返水 5'),
          findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('per-ten-thousand rebate converts to percentage, dark=$dark',
        (tester) async {
      final api = SangongTestApi()
        ..respond = (_) => {
              'summary': <String, dynamic>{},
              'version': 1,
              'nextBeforeId': 0,
              'members': [
                {..._member(), 'rebatePer10000': 50}
              ],
            };
      final runtime = SangongRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(tester, runtime, const SangongAgentDashboardPage(),
          dark: dark);
      expect(find.text('—'), findsWidgets,
          reason: 'Omitted optional financial metrics are unknown, not zero.');
      await tester.scrollUntilVisible(find.textContaining('返水 0.50%'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.textContaining('返水 0.50%'), findsOneWidget);
      expect(find.textContaining('返水 50%'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('explicit percentage takes precedence over per-ten-thousand rate',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'summary': <String, dynamic>{},
            'version': 1,
            'nextBeforeId': 0,
            'members': [
              {..._member(), 'rebatePct': 2, 'rebatePer10000': 50}
            ],
          };
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentDashboardPage());
    await tester.scrollUntilVisible(find.textContaining('返水 2%'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('返水 2%'), findsOneWidget);
  });

  testWidgets('malformed dashboard renders an error instead of zero statistics',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => <String, dynamic>{};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentDashboardPage());
    expect(find.text('返回数据格式无效，请重试'), findsOneWidget);
    expect(find.text('团队总余额'), findsNothing);
    expect(find.text('暂无下级'), findsNothing);
  });

  testWidgets('transfer locks dialogs and remains disabled during submission',
      (tester) async {
    final response = Completer<Map<String, dynamic>>();
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/commands/agent.transfer')
          ? response.future
          : _team();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentTeamPage());
    final callback = _transferButton(tester).onPressed!;
    await tester.tap(find.byTooltip('划转积分'));
    await tester.pumpAndSettle();
    expect(_transferButton(tester).onPressed, isNull);
    callback();
    await flushSangong(tester);
    expect(find.byType(CupertinoTextField), findsOneWidget);
    await _confirmTransfer(tester);
    expect(api.count('/commands/agent.transfer'), 1);
    expect(_transferButton(tester).onPressed, isNull);
    callback();
    await flushSangong(tester);
    expect(api.count('/commands/agent.transfer'), 1);
    expect(find.byType(CupertinoTextField), findsNothing);
    response.complete({
      'ok': true,
      'requestId': api.calls
          .lastWhere((c) => c.path.endsWith('/commands/agent.transfer'))
          .body!['requestId'],
      'data': {'referenceId': 'transfer-42', 'fromBalance': 90}
    });
    await flushSangong(tester);
    expect(_transferButton(tester).onPressed, isNotNull);
    expect(api.count('/commands/agent.transfer'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling the transfer prompt releases its lock',
      (tester) async {
    final api = SangongTestApi()..respond = (_) => _team();
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentTeamPage());
    await tester.tap(find.byTooltip('划转积分'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '取消'));
    await tester.pumpAndSettle();
    expect(_transferButton(tester).onPressed, isNotNull);
    expect(api.count('/commands/agent.transfer'), 0);
  });

  testWidgets('revocation while confirming a transfer prevents submission',
      (tester) async {
    var current = true;
    final api = SangongTestApi()..respond = (_) => _team();
    final runtime =
        SangongRuntime(sangongTestContext(api, current: () => current));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, const SangongAgentTeamPage());
    await tester.tap(find.byTooltip('划转积分'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(CupertinoTextField), '10');
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '下一步'));
    await tester.pumpAndSettle();
    current = false;
    await tester.tap(find.widgetWithText(CupertinoDialogAction, '确认划转'));
    await tester.pumpAndSettle();
    expect(api.count('/commands/agent.transfer'), 0);
    expect(tester.takeException(), isNull);
  });

  for (final change in ['tenant', 'capabilities']) {
    testWidgets(
        'changing $change with access intact expires transfer confirmation',
        (tester) async {
      final api = SangongTestApi()..respond = (_) => _team();
      final runtime = SangongRuntime(sangongTestContext(api));
      addTearDown(runtime.dispose);
      addTearDown(() => unmountSangong(tester));
      await pumpSangongPage(tester, runtime, const SangongAgentTeamPage());
      await tester.tap(find.byTooltip('划转积分'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(CupertinoTextField), '10');
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '下一步'));
      await tester.pumpAndSettle();
      if (change == 'tenant') {
        runtime.http.setTenantId('tenant-other');
      } else {
        runtime.updateContext(sangongTestContext(api, capabilityVersion: 2));
      }
      expect(runtime.canOpenAgent, isTrue);
      await tester.tap(find.widgetWithText(CupertinoDialogAction, '确认划转'));
      await tester.pumpAndSettle();
      expect(api.count('/commands/agent.transfer'), 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rebate amount acknowledges the request without asserting credit',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.path.endsWith('/commands/rebate.claim')
          ? {
              'ok': true,
              'requestId': call.body!['requestId'],
              'data': {'amount': 7}
            }
          : {'member': _member(id: 'owner')};
    final runtime =
        SangongRuntime(sangongTestContext(api, canViewHistory: false));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        SangongAgentMemberDetailPage(
            member: SangongTeamMemberDto.fromJson(_member(id: 'owner'))));
    final button = find.text('申请返水');
    await tester.scrollUntilVisible(button, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(button);
    await flushSangong(tester);
    expect(find.text('返水申请已提交，金额 ¥7，请刷新确认到账'), findsOneWidget);
    expect(find.textContaining('返水申请成功，到账'), findsNothing);
    expect(api.count('/commands/rebate.claim'), 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'latest-data failures remain visible after successful daily fallback',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) =>
          call.path.endsWith('/member') ? <String, dynamic>{} : {'days': []};
    final runtime = SangongRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(
        tester,
        runtime,
        SangongAgentMemberDetailPage(
            member: SangongTeamMemberDto.fromJson(_member())));
    expect(find.text('返回数据格式无效，请重试'), findsOneWidget);
    expect(api.count('/member-daily'), 1);
    expect(tester.takeException(), isNull);
  });
}
