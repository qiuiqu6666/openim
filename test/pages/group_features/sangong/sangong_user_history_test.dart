import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_user_flow_result.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'sangong_test_support.dart';

const _page = SangongUserDetailPage(
    user: SangongAdminUserReport(
        userId: 19, imUserId: 'im_target', nickname: '目标用户'));

void main() {
  test('coverage counts raw rows, preserves server totals and cursor', () {
    final result = SangongUserFlowResult.fromJson(sangongUserReport(
        imUserId: 'im_target',
        total: 600,
        nextBeforeId: 100,
        entries: List.generate(
            500,
            (i) => {
                  'ledgerId': 600 - i,
                  'type': 'rebate_player',
                  'amount': 10,
                  'createdAt': '2026-10-06T00:00:00+08:00',
                })));
    expect(result.report.scoreEntries, isEmpty);
    expect(result.returnedLedgerCount, 500);
    expect(result.reachedLedgerLimit, isTrue);
    expect(result.coverageMessage(batch: false), contains('共 600 条账变'));
    expect(result.coverageMessage(batch: false), contains('完整金额以汇总为准'));
    expect(result.coverageMessage(batch: true), contains('本批次'));
  });

  testWidgets(
      'business-date summary and cursor entries share one request scope',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-report')) {
          final before = call.query?['beforeId'] as int? ?? 601;
          final start = before - 1;
          return sangongUserReport(
              imUserId: 'im_target',
              total: 600,
              nextBeforeId: start - 99,
              summary: {'todayUp': 9000},
              entries: List.generate(
                  100,
                  (i) => {
                        'ledgerId': start - i,
                        'type': 'rebate_player',
                        'amount': 10,
                        'createdAt': '2026-10-07T01:00:00+08:00',
                      }));
        }
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, _page);
    final requests =
        api.calls.where((c) => c.path.endsWith('/user-report')).toList();
    expect(requests.length, 5);
    final day = requests.first.query?['date'];
    expect(day, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(requests.map((c) => c.query?['beforeId']).toList(),
        [null, 501, 401, 301, 201]);
    for (final call in requests) {
      expect(call.query?['date'], day);
      expect(call.query?['imUserId'], 'im_target');
      expect(call.query?['limit'], 100);
      expect(call.query?.containsKey('sessionId'), isFalse);
    }
    expect(api.count('/user'), 0,
        reason: 'Profile is included in the aggregate.');
    expect(api.count('/user-hierarchy'), 0);
    expect(find.text('经营日汇总'), findsOneWidget);
    expect(find.text('9000'), findsOneWidget);
    final notice = tester
        .widget<Text>(find.byKey(const ValueKey('sangong-flow-coverage')))
        .data!;
    expect(notice, contains('已显示 500 条'));
    expect(notice, contains('共 600 条'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'selected session replaces the date scope for both totals and details',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/sessions')) {
          return {
            'sessions': [
              {'id': 2, 'batchNo': 'batch-2'}
            ]
          };
        }
        if (call.path.endsWith('/snapshot')) {
          return {
            'session': {'id': 2},
            'round': null
          };
        }
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, _page);
    await tester.tap(find.text('开机批次'));
    await flushSangong(tester);
    expect(api.calls.lastWhere((c) => c.path.endsWith('/user-report')).query,
        {'imUserId': 'im_target', 'sessionId': 2, 'limit': 100});
    final notice = tester
        .widget<Text>(find.byKey(const ValueKey('sangong-flow-coverage')))
        .data!;
    expect(notice, contains('本批次共 0 条'));
    expect(notice, contains('账变已全部读取'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 by 480 ledger scrolls header and keeps every tab reachable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today =
        sangongReportDate(DateTime.now().toUtc().add(const Duration(hours: 8)));
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-report')) {
          return sangongUserReport(imUserId: 'im_target', summary: {
            'todayUp': 100
          }, entries: [
            {
              'ledgerId': 1,
              'type': 'bet_hold',
              'amount': -10,
              'createdAt': '${today}T01:00:00+08:00'
            },
            {
              'ledgerId': 2,
              'type': 'settle_banker',
              'amount': 20,
              'createdAt': '${today}T02:00:00+08:00'
            },
            {
              'ledgerId': 3,
              'type': 'admin_credit',
              'amount': 100,
              'createdAt': '${today}T03:00:00+08:00'
            },
          ]);
        }
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    addTearDown(runtime.dispose);
    addTearDown(() => unmountSangong(tester));
    await pumpSangongPage(tester, runtime, _page, dark: true);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    for (final label in ['下注流水', '庄流水', '上下分']) {
      final tab =
          find.descendant(of: find.byType(TabBar), matching: find.text(label));
      expect(tab.hitTestable(), findsOneWidget);
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.drag(find.byType(NestedScrollView), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('设置额度').hitTestable(), findsOneWidget);
  });
}
