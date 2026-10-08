import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_admin_models.dart';
import 'package:openim/pages/group_features/sangong/models/sangong_account_flow_entry.dart';
import 'package:openim/pages/group_features/sangong/widgets/sangong_account_flow_list.dart';
import 'package:openim/pages/group_features/sangong/report_center/widgets/report_widgets.dart';

Map<String, dynamic> rebateRow({bool automatic = false}) => {
      'ledgerId': automatic ? 2 : 1,
      'type': 'rebate_player',
      'amount': 100,
      'balanceAfter': 1100,
      'rebate': {
        'turnover': 10000,
        'rate': '1.0000',
        'amount': 100,
        'claimType': automatic ? 'AUTO' : 'MANUAL',
        'accountType': 'PLAYER_REBATE',
        'turnoverBasis': 'unclaimed'
      },
    };

void main() {
  test(
      'manual and automatic rebates belong in score list without changing manual up totals',
      () {
    final flow = SangongUserFlowReport.fromJson({
      'entries': [
        rebateRow(),
        rebateRow(automatic: true),
        {'ledgerId': 3, 'type': 'rebate_player_void', 'amount': -100},
      ]
    });
    expect(flow.scoreEntries.length, 3);
    expect(flow.betEntries, isEmpty);
    expect(flow.scoreEntries.where((e) => e.isCredit), isEmpty);
    expect(flow.scoreEntries.last.rebate?.rateLabel, '1%');
    expect(flow.scoreEntries.last.rebate?.turnover, 10000);
  });

  for (final automatic in [false, true]) {
    testWidgets(
        'score list displays frozen rebate receipt automatic=$automatic',
        (tester) async {
      final entry =
          SangongAccountFlowEntry.fromJson(rebateRow(automatic: automatic));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SangongAccountFlowList(entries: [entry], bets: false))));
      expect(find.text(automatic ? '关机自动返水' : '用户申请返水'), findsOneWidget);
      expect(find.text('本次返水流水：10000'), findsOneWidget);
      expect(find.text('返水比例：1%'), findsOneWidget);
      expect(find.text('返水金额：100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rate change settlement displays frozen old rate in score list',
      (tester) async {
    final raw = rebateRow();
    (raw['rebate'] as Map<String, dynamic>)['claimType'] = 'RATE_CHANGE';
    final entry = SangongAccountFlowEntry.fromJson(raw);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SangongAccountFlowList(entries: [entry], bets: false))));
    expect(find.text('修改比例前结清返水'), findsOneWidget);
    expect(find.text('返水比例：1%'), findsOneWidget);
    expect(find.text('返水金额：100'), findsOneWidget);
    expect(find.text('用户申请返水'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('old receipts display actual amount without inventing a rate',
      (tester) async {
    final raw = rebateRow()..remove('rebate');
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: ReportLedgerTile(raw))));
    expect(find.text('返水比例：未记录'), findsOneWidget);
    expect(find.text('本次返水流水：未记录'), findsOneWidget);
    expect(find.text('返水金额：100'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
