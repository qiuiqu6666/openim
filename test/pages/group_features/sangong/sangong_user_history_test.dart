import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_user_flow_result.dart';
import 'package:openim/pages/group_features/sangong/pages/sangong_user_detail_page.dart';
import 'sangong_test_support.dart';

void main() {
  test('history coverage counts raw ledger rows before filtering type/date',
      () {
    final result = SangongUserFlowResult.fromJson({
      'flow': {
        'entries': List.generate(
            500,
            (id) => {
                  'ledgerId': id + 1,
                  'type': 'rebate_player',
                  'createdAt': '2026-10-06T00:00:00+08:00',
                }),
        'ledgerFlow': List.generate(500, (id) => {'ledgerId': id + 1}),
      }
    });
    expect(result.report.scoreEntries, isEmpty);
    expect(result.returnedLedgerCount, 500,
        reason: 'Alias arrays must not double-count the same ledger rows.');
    expect(result.reachedLedgerLimit, isTrue);
    expect(result.coverageMessage(batch: false), contains('较早明细可能缺失'));
    expect(result.coverageMessage(batch: false), contains('没有明细不表示'));
    expect(result.coverageMessage(batch: true), contains('本批次最近账变'));
    expect(result.coverageMessage(batch: true), isNot(contains('按开机批次查询')));
  });

  testWidgets(
      'date totals use the real date contract; details expose latest cap',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-detail')) {
          return {
            'user': {'userId': 19, 'imUserId': 'im_target'}
          };
        }
        if (call.path.endsWith('/sessions')) return {'sessions': []};
        if (call.path.endsWith('/user-hierarchy')) {
          return {
            'members': [
              {'imUserId': 'im_target', 'todayUp': 9000}
            ]
          };
        }
        if (call.path.endsWith('/user-flow')) {
          return {
            'flow': {
              'entries': List.generate(
                  500,
                  (id) => {
                        'ledgerId': id + 1,
                        'type': 'rebate_player',
                        'createdAt': '2026-10-06T00:00:00+08:00',
                      }),
            }
          };
        }
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(
        tester,
        runtime,
        const SangongUserDetailPage(
            user: SangongAdminUserReport(
                userId: 19, imUserId: 'im_target', nickname: '目标用户')));
    final summary =
        api.calls.firstWhere((c) => c.path.endsWith('/user-hierarchy'));
    final detail = api.calls.firstWhere((c) => c.path.endsWith('/user-flow'));
    expect(summary.query?['date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(detail.query, {'imUserId': 'im_target'},
        reason: 'The confirmed flow API has no date/page/cursor parameter.');
    expect(find.text('每日汇总'), findsOneWidget);
    expect(find.text('9000'), findsOneWidget);
    final notice = tester
        .widget<Text>(find.byKey(const ValueKey('sangong-flow-coverage')))
        .data!;
    expect(notice, contains('已达到 500 条上限'));
    expect(notice, contains('没有明细不表示当天没有交易'));
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });

  testWidgets(
      'batch filtering uses sessionId without pretending date pagination',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (call) {
        if (call.path.endsWith('/user-detail')) return {'user': {}};
        if (call.path.endsWith('/sessions')) {
          return {
            'sessions': [
              {'id': 2, 'batchNo': 'batch-2'}
            ]
          };
        }
        if (call.path.endsWith('/session')) {
          return {
            'session': {'id': 2},
            'round': null
          };
        }
        if (call.path.endsWith('/user-hierarchy')) return {'members': []};
        if (call.path.endsWith('/user-flow')) {
          return {
            'flow': {'entries': []}
          };
        }
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(
        tester,
        runtime,
        const SangongUserDetailPage(
            user: SangongAdminUserReport(userId: 19, imUserId: 'im_target')));
    await tester.tap(find.text('开机批次'));
    await flushSangong(tester);
    expect(api.calls.lastWhere((c) => c.path.endsWith('/user-flow')).query,
        {'imUserId': 'im_target', 'sessionId': 2});
    expect(api.calls.lastWhere((c) => c.path.endsWith('/user-hierarchy')).query,
        {'imUserId': 'im_target', 'sessionId': 2});
    final notice = tester
        .widget<Text>(find.byKey(const ValueKey('sangong-flow-coverage')))
        .data!;
    expect(notice, contains('本批次最近账变'));
    expect(notice, contains('较早明细可能缺失'));
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
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
        if (call.path.endsWith('/user-detail')) {
          return {
            'user': {'userId': 19, 'imUserId': 'im_target'}
          };
        }
        if (call.path.endsWith('/sessions')) return {'sessions': []};
        if (call.path.endsWith('/user-hierarchy')) {
          return {
            'members': [
              {'imUserId': 'im_target', 'todayUp': 100}
            ]
          };
        }
        if (call.path.endsWith('/user-flow')) {
          return {
            'flow': {
              'entries': [
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
              ],
            }
          };
        }
        return sangongFixtureResponse(call);
      };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(
        tester,
        runtime,
        const SangongUserDetailPage(
            user: SangongAdminUserReport(userId: 19, imUserId: 'im_target')),
        dark: true);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(NestedScrollView), const Offset(0, -900));
    await tester.pumpAndSettle();
    for (final tab in ['下注流水', '庄流水', '上下分']) {
      final finder =
          find.descendant(of: find.byType(TabBar), matching: find.text(tab));
      expect(finder.hitTestable(), findsOneWidget);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    await tester.drag(find.byType(NestedScrollView), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('设置额度').hitTestable(), findsOneWidget);
    await unmountSangong(tester);
    runtime.dispose();
  });
}
