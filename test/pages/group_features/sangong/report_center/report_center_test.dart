import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/report_center/data/report_query_controller.dart';
import 'package:openim/pages/group_features/sangong/report_center/pages/report_center_page.dart';
import '../sangong_test_support.dart';

Map<String, dynamic> managementSummary() => {
      'version': 7,
      'hallName': '测试厅',
      'groupId': 'group-sangong',
      'session': {
        'id': 2,
        'batchNo': '2026100801',
        'businessDate': '2026-10-08'
      },
      'summary': {
        'userCount': 8,
        'currentBalance': 1200,
        'teamCount': 2,
        'roundCount': 3,
        'settledCount': 2,
        'totalBets': 900,
        'rake': 54,
        'bankerNet': 246,
        'paidRebate': 10,
        'ledgerCount': 30
      },
      'ledgerTypes': [
        {'type': 'bet_hold', 'count': 3, 'amount': -900}
      ],
      'state': {
        'status': 'running',
        'placed': {'grandTotal': 100},
        'settings': {'doorCount': 6, 'rakePercent': 6}
      },
      'asOf': '2026-10-08T10:00:00Z',
    };

void main() {
  for (final dark in [false, true]) {
    testWidgets('helper report center loads only visible tab dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SangongTestApi()
        ..respond = (call) {
          if (call.path.endsWith('/management-summary'))
            return managementSummary();
          if (call.path.endsWith('/sessions'))
            return {'version': 7, 'sessions': [], 'nextBeforeId': 0};
          if (call.path.endsWith('/management-users')) {
            expect(call.query?['sessionId'], 2);
            return {
              'version': 7,
              'users': [
                {
                  'userId': 19,
                  'imUserId': 'im_target',
                  'nickname': '用户甲',
                  'balance': 1000,
                  'group': {'name': 'A组'},
                  'childrenCount': 0,
                  'playerTurnover': 100,
                  'profitLoss': -20
                }
              ],
              'nextBeforeId': 0
            };
          }
          return sangongFixtureResponse(call);
        };
      final runtime = sangongTestRuntime(
          sangongTestContext(api, canConfigure: false, canManage: true));
      await pumpSangongPage(tester, runtime, const SangongReportCenterPage(),
          dark: dark);
      expect(find.text('报表中心'), findsOneWidget);
      expect(find.text('测试厅'), findsOneWidget);
      expect(api.count('/management-users'), 0);
      await tester.tap(find.text('用户'));
      await flushSangong(tester);
      expect(find.text('用户甲'), findsOneWidget);
      expect(api.count('/management-users'), 1);
      expect(api.count('/management-teams'), 0);
      expect(tester.takeException(), isNull);
      await unmountSangong(tester);
      runtime.dispose();
    });
  }

  testWidgets('version change never merges two ledger pages', (tester) async {
    final api = SangongTestApi()
      ..respond = (call) => call.query?['beforeId'] == null
          ? {
              'version': 7,
              'entries': [
                {'id': 20, 'amount': 100}
              ],
              'nextBeforeId': 20
            }
          : {
              'version': 8,
              'entries': [
                {'id': 19, 'amount': 200}
              ],
              'nextBeforeId': 0
            };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final query = ReportQueryController(runtime, 'ledger',
        listKey: 'entries', query: {'sessionId': 2});
    await completeSangongRequest(tester, query.load());
    expect(query.rows.length, 1);
    await completeSangongRequest(tester, query.load(more: true));
    expect(query.rows, isEmpty);
    expect(query.error, isNotNull);
    query.dispose();
    runtime.dispose();
  });

  testWidgets('late response is discarded after group change', (tester) async {
    final pending = Completer<dynamic>();
    final api = SangongTestApi()..respond = (_) => pending.future;
    final runtime = sangongTestRuntime(sangongTestContext(api));
    final query =
        ReportQueryController(runtime, 'management-users', listKey: 'users');
    final request = query.load();
    await flushSangong(tester);
    runtime.updateContext(sangongTestContext(api,
        groupID: 'another-group', tenantID: 'another-tenant'));
    pending.complete({
      'version': 7,
      'users': [
        {'nickname': 'old private user'}
      ],
      'nextBeforeId': 0
    });
    await completeSangongRequest(tester, request);
    expect(query.rows, isEmpty);
    expect(query.invalid, isTrue);
    query.dispose();
    runtime.dispose();
  });
}
