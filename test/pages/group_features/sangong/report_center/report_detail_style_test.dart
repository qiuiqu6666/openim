import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/group_features/sangong/report_center/pages/report_detail_page.dart';
import 'package:openim/pages/group_features/sangong/report_center/widgets/report_widgets.dart';
import '../sangong_test_support.dart';

void main() {
  test('amounts and door bets use readable labels', () {
    expect(reportValue(1234567), '1,234,567');
    expect(reportSigned(-1234), '-1,234');
    expect(reportSigned(1234), '+1,234');
    expect(reportValue(null), '—');
    expect(reportDoorBets({'6': 9000, '1': 300}), '1门 300 · 6门 9,000');
  });

  for (final dark in [false, true]) {
    testWidgets('round breakdown is readable on small screen dark=$dark',
        (tester) async {
      tester.view.physicalSize = const Size(320, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SangongTestApi()
        ..respond = (_) => {
              'version': 7,
              'round': {
                'periodNo': 1,
                'bankerDoor': 1,
                'status': 'settled',
                'sessionId': 2
              },
              'draws': [
                {'door': 1, 'amountHundredths': 9964}
              ],
              'settlement': {
                'bankerNickname': '庄家甲',
                'grandTotal': 12000,
                'bankerNet': -2000,
                'rake': 720,
                'bankers': [],
                'players': [
                  {
                    'imUserId': 'user1',
                    'nickname': '用户甲',
                    'net': 2000,
                    'balanceBefore': 10000,
                    'balanceAfter': 12000,
                    'totalBet': 300,
                    'doorBets': {'2': 300},
                  }
                ],
              },
            };
      final runtime = sangongTestRuntime(sangongTestContext(api));
      await pumpSangongPage(
          tester,
          runtime,
          Builder(
              builder: (context) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.3)),
                  child: const SangongReportDetailPage(
                      title: '第1期明细',
                      resource: 'management-round',
                      query: {'roundId': 1}))),
          dark: dark,
          platform: TargetPlatform.iOS);
      expect(find.text('闲家总下注'), findsOneWidget);
      expect(find.text('12,000'), findsOneWidget);
      expect(find.text('1门 · 庄'), findsOneWidget);
      expect(find.text('99.64'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('用户甲'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('用户甲'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('2门 300'));
      expect(find.text('2门 300'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountSangong(tester);
      runtime.dispose();
    });
  }

  testWidgets('ledger filter can clear a category opened from overview',
      (tester) async {
    final api = SangongTestApi()
      ..respond = (_) => {
            'version': 7,
            'entries': [],
            'nextBeforeId': 0,
          };
    final runtime = sangongTestRuntime(sangongTestContext(api));
    await pumpSangongPage(
        tester,
        runtime,
        const SangongReportDetailPage(
            title: '退款',
            resource: 'ledger',
            listKey: 'entries',
            query: {'sessionId': 2, 'type': 'bet_cancel'}));
    tester
        .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>))
        .onChanged!('');
    await flushSangong(tester);
    expect(api.calls.last.query?['type'], '');
    expect(api.calls.last.query?['sessionId'], 2);
    expect(tester.takeException(), isNull);
    await unmountSangong(tester);
    runtime.dispose();
  });
}
