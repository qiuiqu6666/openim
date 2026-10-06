import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';
import 'package:openim/pages/wallet/wallet_time.dart';

import 'fixtures/wallet_record_fixtures.dart';
import 'support/wallet_record_test_support.dart';

void main() {
  test('record entry retains an unrestricted default coin', () {
    expect(const WalletRecordScreen().initialCoin, isNull);
  });

  testWidgets('default ledger groups real months across years newest first',
      (tester) async {
    final repository = RecordTestRepository();
    await pumpWalletRecords(tester,
        repository: repository, size: const Size(390, 2400));
    await tester.pumpAndSettle();
    expect(find.text('余额变动明细'), findsOneWidget);
    expectRecordRequests(repository, 1);
    const months = ['2026-10', '2026-01', '2025-12', '2025-01', 'unknown'];
    double previous = -1;
    for (final month in months) {
      final heading = walletRecordKey('wallet-record-month-$month');
      expect(heading, findsOneWidget);
      final top = tester.getTopLeft(heading).dy;
      expect(top, greaterThan(previous));
      previous = top;
      expect(walletRecordKey('wallet-record-group-$month'), findsOneWidget);
    }
    expect(
        tester.getTopLeft(walletRecordKey('wallet-record-january-newer')).dy,
        lessThan(tester
            .getTopLeft(walletRecordKey('wallet-record-january-older'))
            .dy));
    for (final item in walletRecordFixtures) {
      expect(walletRecordKey('wallet-record-${item.id}'), findsOneWidget,
          reason: 'The default view includes old and undated records.');
    }
    for (final entry in const {
      '2026-10': 2,
      '2026-01': 2,
      '2025-12': 1,
      '2025-01': 1,
      'unknown': 1
    }.entries) {
      expect(
          find.descendant(
              of: walletRecordKey('wallet-record-group-${entry.key}'),
              matching: find.byType(Divider)),
          findsNWidgets(entry.value - 1),
          reason: 'Only adjacent rows in one month have a separator.');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('three direction tabs filter income flags locally',
      (tester) async {
    final repository = RecordTestRepository();
    await pumpWalletRecords(tester,
        repository: repository, size: const Size(390, 2400));
    await tester.pumpAndSettle();
    for (final direction in ['income', 'expenditure', 'all']) {
      await tester.tap(walletRecordKey('wallet-record-tab-$direction'));
      await tester.pumpAndSettle();
      for (final item in walletRecordFixtures) {
        final visible = direction == 'all' ||
            (direction == 'income' ? item.income : !item.income);
        expect(walletRecordKey('wallet-record-${item.id}'),
            visible ? findsOneWidget : findsNothing,
            reason:
                '${item.id} has ${item.type} type but income=${item.income}');
      }
      expectRecordRequests(repository, 1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('month selection retains the year and can return to all months',
      (tester) async {
    final repository = RecordTestRepository();
    await pumpWalletRecords(tester,
        repository: repository, size: const Size(390, 2400));
    await tester.pumpAndSettle();
    await _selectMonth(tester, from: '2026-10', value: '2026-01');
    expect(walletRecordKey('wallet-record-month-2026-01'), findsOneWidget);
    expect(walletRecordKey('wallet-record-january-newer'), findsOneWidget);
    expect(walletRecordKey('wallet-record-january-older'), findsOneWidget);
    for (final id in [
      'old-january',
      'october-incoming',
      'failed-outgoing',
      'unknown-time'
    ]) {
      expect(walletRecordKey('wallet-record-$id'), findsNothing);
    }
    await _selectMonth(tester, from: '2026-01', value: 'all');
    for (final item in walletRecordFixtures) {
      expect(walletRecordKey('wallet-record-${item.id}'), findsOneWidget);
    }
    expectRecordRequests(repository, 1);
  });

  for (final coin in ['99', '元']) {
    testWidgets('initial $coin coin matches platform aliases only',
        (tester) async {
      final repository = RecordTestRepository();
      await pumpWalletRecords(tester,
          repository: repository,
          initialCoin: coin,
          size: const Size(390, 2400));
      await tester.pumpAndSettle();
      for (final item in walletRecordFixtures) {
        expect(
            walletRecordKey('wallet-record-${item.id}'),
            item.coin == '99' || item.coin == '元'
                ? findsOneWidget
                : findsNothing);
      }
      expectRecordRequests(repository, 1);
    });
  }

  testWidgets(
      'amounts round to two decimals, normalize signs and show unknown balances',
      (tester) async {
    await pumpWalletRecords(tester,
        repository: RecordTestRepository(), size: const Size(390, 2400));
    await tester.pumpAndSettle();
    const expected = {
      'october-incoming': '+28.50',
      'october-outgoing': '-8.00',
      'january-older': '+1.25 USDT',
      'january-newer': '-12.35 USDT',
      'old-january': '+50.00',
      'failed-outgoing': '-8.01 USDT',
      'unknown-time': '+9.00 USDT',
    };
    for (final entry in expected.entries) {
      expect(
          tester
              .widget<Text>(
                  walletRecordKey('wallet-record-amount-${entry.key}'))
              .data
              ?.replaceAll('\u200B', ''),
          entry.value);
      expect(
          tester
              .widget<Text>(
                  walletRecordKey('wallet-record-balance-${entry.key}'))
              .data,
          '余额 --',
          reason: 'The ledger API has no balance-after field.');
    }
    for (final item in walletRecordFixtures) {
      final time = tester
          .widget<Text>(walletRecordKey('wallet-record-time-${item.id}'))
          .data;
      expect(
          time,
          anyOf(
              item.time.isEmpty ? '--' : item.time,
              formatWalletApiDateTime(item.time,
                  pattern: 'yyyy-MM-dd HH:mm:ss')));
    }
    expect(find.text('处理中'), findsOneWidget);
    expect(find.text('失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'row opens the existing detail route with the exact repository item',
      (tester) async {
    final observer = RecordRouteObserver();
    final item = walletRecordFixtures
        .firstWhere((item) => item.id == 'october-incoming');
    await pumpWalletRecords(tester,
        repository: RecordTestRepository(), observer: observer);
    await tester.pumpAndSettle();
    await tester.tap(walletRecordKey('wallet-record-${item.id}'));
    final pushed = observer.lastPush;
    expect(pushed, isA<AppMaterialPageRoute<void>>());
    final destination = (pushed! as PageRouteBuilder).pageBuilder(
      tester.element(find.byType(WalletRecordScreen)),
      const AlwaysStoppedAnimation(1),
      const AlwaysStoppedAnimation(0),
    );
    expect(destination, isA<WalletRecordDetailScreen>());
    expect((destination as WalletRecordDetailScreen).item, same(item));
    observer.navigator!.removeRoute(pushed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _selectMonth(WidgetTester tester,
    {required String from, required String value}) async {
  await tester.tap(walletRecordKey('wallet-record-month-picker-$from'));
  await tester.pumpAndSettle();
  await tester.tap(find.byWidgetPredicate(
      (widget) => widget is PopupMenuItem<String> && widget.value == value));
  await tester.pumpAndSettle();
}
