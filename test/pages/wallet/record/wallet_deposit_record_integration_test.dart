import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/order/wallet_order_events.dart';
import 'package:openim/pages/wallet/record/wallet_record_detail_screen.dart';
import 'package:openim/pages/wallet/record/widgets/wallet_record_row.dart';

import '../data/wallet_fund_test_transport.dart';
import 'journals/wallet_journal_entry_test.dart' show journalTestJson;
import 'support/wallet_record_test_support.dart';

void main() {
  testWidgets(
      'real journals retain duplicate tx hashes and display ledger timestamps',
      (tester) async {
    final transport = WalletFundTestTransport();
    addTearDown(transport.close);
    final events = _depositJournals();
    transport.respond(_journalPage(events));
    final repository = WalletFundRepository(
        api: transport.wallet, accountProvider: () => 'test:owner');
    await pumpWalletRecords(tester, repository: repository);
    await settleWalletRecordImages(tester);
    expect(walletRecordKey('wallet-record-month-unknown'), findsNothing);
    expect(find.text('时间未知'), findsNothing);
    expect(walletRecordKey('wallet-record-month-2026-10'), findsOneWidget);
    expect(walletRecordKey('wallet-record-source-notice'), findsNothing);
    expect(find.textContaining('最近100条'), findsNothing);
    for (final event in events) {
      final id = event['id'] as String;
      final row = walletRecordKey('wallet-record-$id');
      await tester.ensureVisible(row);
      expect(row, findsOneWidget);
      expect(
          tester.widget<Text>(walletRecordKey('wallet-record-time-$id')).data,
          startsWith('2026-10-'));
      expect(
          tester
              .widget<Text>(walletRecordKey('wallet-record-balance-$id'))
              .data,
          event['afterAvailable'] == null
              ? '可用余额 --'
              : '可用余额 ${event['afterAvailable']} ${event['currency']}');
    }
    final rows =
        tester.widgetList<WalletRecordRow>(find.byType(WalletRecordRow));
    expect(rows.map((row) => row.item.id).toSet(), hasLength(3));
    expect(rows.take(2).map((row) => row.item.hash), ['same-tx', 'same-tx']);
    expect(rows.last.item.journal!.direction, 'expense');
    expect(rows.last.item.journal!.type, 'deposit_reversal');
    final first = walletRecordKey('wallet-record-event-deposit-usdt');
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    final detail = tester.widget<WalletRecordDetailScreen>(
        find.byType(WalletRecordDetailScreen));
    expect(detail.item.hash, 'same-tx');
    expect(detail.item.amount, '12.345678');
    expect(detail.item.journal!.createdAt, events.first['createdAt']);
    expect(detail.item.orderNo, 'deposit-order');
    expect(detail.item.fee, isEmpty);
    expect(transport.requests, hasLength(1));
    final request = transport.requests.single;
    expect(request.path, 'https://chat.example.test/chat/fund/journals');
    expect(request.method, 'GET');
    expect(request.headers['token'], 'chat-token');
    expect(request.headers['operationID'], isNotEmpty);
    expect(request.queryParameters, {'limit': 20});
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'record refresh events defer in background and cannot refresh another account',
      (tester) async {
    var account = 'test:record-owner';
    final transport = WalletFundTestTransport();
    addTearDown(transport.close);
    transport.respond(_journalPage(_depositJournals()));
    final repository = WalletFundRepository(
        api: transport.wallet, accountProvider: () => account);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await pumpWalletRecords(tester, repository: repository);
    await settleWalletRecordImages(tester);
    WalletOrderEvents.notifyRecord(accountKey: 'test:other');
    await tester.pump();
    expect(transport.requests, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    WalletOrderEvents.notifyRecord(accountKey: account);
    await tester.pump();
    expect(transport.requests, hasLength(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(transport.requests, hasLength(2));
    expect(
        transport.requests
            .map((request) => request.headers['operationID'])
            .toSet(),
        hasLength(2));
    expect(
        transport.requests.every((request) =>
            request.path.endsWith('/chat/fund/journals') &&
            !request.queryParameters.containsKey('userID')),
        isTrue);
    account = 'test:new-owner';
    WalletOrderEvents.notifyRecord(accountKey: 'test:record-owner');
    await tester.pump();
    expect(transport.requests, hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
    WalletOrderEvents.notifyRecord(accountKey: account);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _journalPage(List<Map<String, dynamic>> events) => {
      'items': events,
      'limit': 20,
      'hasMore': false,
      'nextCursor': '',
    };

List<Map<String, dynamic>> _depositJournals() => [
      journalTestJson(id: 'event-deposit-usdt')
        ..addAll({
          'currency': 'USDT',
          'bizType': 'deposit',
          'type': 'deposit',
          'title': '链上充值',
          'direction': 'income',
          'amount': '12.345678',
          'availableDelta': '12.345678',
          'frozenDelta': '0',
          'assetDelta': '12.345678',
          'afterAvailable': '12.345678',
          'createdAt': 1791244800000,
          'bizID': 'deposit-usdt',
          'orderID': 'deposit-order',
          'groupID': '',
          'remark': '',
          'orderStatus': '',
          'chainTxID': 'same-tx',
        }),
      journalTestJson(id: 'event-deposit-trx')
        ..addAll({
          'currency': 'TRX',
          'bizType': 'deposit',
          'type': 'deposit',
          'title': '链上充值',
          'direction': 'income',
          'amount': '8.010001',
          'availableDelta': '8.010001',
          'frozenDelta': '0',
          'assetDelta': '8.010001',
          'createdAt': 1791244799000,
          'bizID': 'deposit-trx',
          'orderID': 'deposit-order',
          'groupID': '',
          'remark': '',
          'orderStatus': '',
          'chainTxID': 'same-tx',
        }),
      journalTestJson(id: 'event-deposit-reversal')
        ..addAll({
          'currency': 'USDT',
          'bizType': 'deposit_reversal',
          'type': 'deposit_reversal',
          'title': '充值撤销',
          'direction': 'expense',
          'amount': '1.25',
          'availableDelta': '-1.25',
          'frozenDelta': '0',
          'assetDelta': '-1.25',
          'createdAt': 1791244798000,
          'bizID': 'reverted-deposit',
          'orderID': '',
          'groupID': '',
          'remark': '',
          'orderStatus': '',
          'chainTxID': 'reverted-tx',
        }),
    ];
