import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/record/journals/detail/wallet_journal_linked_order_screen.dart';
import 'package:openim/pages/wallet/record/journals/wallet_journal_entry.dart';

import '../support/wallet_record_test_support.dart';
import 'wallet_journal_entry_test.dart' show journalTestJson;

void main() {
  testWidgets('loads the associated order amount rather than its refund amount',
      (tester) async {
    final api = _OrderApi()..respond = (_) async => _order();
    await _pump(tester, api);
    await tester.pumpAndSettle();
    expect(api.requested, ['packet-order']);
    expect(_fieldText(tester, 'amount'), '10 USDT');
    expect(_fieldText(tester, 'id').replaceAll('\u200B', ''), 'packet-order');
    expect(find.text('8 USDT'), findsNothing);
    expect(find.text('已退回'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed read retries once and rebuilding does not repeat it',
      (tester) async {
    final reply = Completer<WalletFundOrder>();
    final api = _OrderApi();
    api.respond = (_) => api.requested.length == 1
        ? Future.error(StateError('private backend diagnostics'))
        : reply.future;
    await _pump(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('private backend diagnostics'), findsNothing);
    final retry = find.byKey(const ValueKey('wallet-journal-order-retry'));
    expect(retry, findsOneWidget);
    await tester.tap(retry);
    await tester.pump();
    expect(api.requested, ['packet-order', 'packet-order']);
    expect(find.byKey(const ValueKey('wallet-journal-order-loading')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.requested, hasLength(2));
    reply.complete(_order());
    await tester.pumpAndSettle();
    expect(_fieldText(tester, 'amount'), '10 USDT');
  });

  testWidgets('a reply from a previous login does not expose its order',
      (tester) async {
    var owner = true;
    final reply = Completer<WalletFundOrder>();
    final api = _OrderApi()..respond = (_) => reply.future;
    await _pump(tester, api, isCurrent: () => owner);
    owner = false;
    reply.complete(_order());
    await tester.pumpAndSettle();
    expect(find.text('10 USDT'), findsNothing);
    expect(
        find.byKey(const ValueKey('wallet-journal-order-retry')), findsNothing);
    expect(find.byKey(const ValueKey('wallet-journal-order-error')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a different order ID is rejected with a usable Chinese retry',
      (tester) async {
    final api = _OrderApi()..respond = (_) async => _order(id: 'another-order');
    await _pump(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('another-order'), findsNothing);
    expect(find.text('暂时无法加载账单，请重试'), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-journal-order-retry')),
        findsOneWidget);
  });

  testWidgets('closing the page safely ignores its pending reply',
      (tester) async {
    final reply = Completer<WalletFundOrder>();
    final api = _OrderApi()..respond = (_) => reply.future;
    await _pump(tester, api);
    await tester.pumpWidget(const SizedBox.shrink());
    reply.complete(_order());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a manually recorded withdrawal does not claim chain confirmation',
      (tester) async {
    final api = _OrderApi()
      ..respond = (_) async => _order(biz: 'withdraw', status: 'withdraw_done');
    await _pump(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('已登记出款'), findsOneWidget);
    expect(find.text('已到账'), findsNothing);
  });

  testWidgets('approved withdrawal shows waiting for payment and real metadata',
      (tester) async {
    final api = _OrderApi()
      ..respond = (_) async => WalletFundOrder(
          orderID: 'packet-order',
          biz: 'withdraw',
          currency: FundCurrency.usdt,
          amount: '10',
          status: 'withdraw_approved',
          toAddress: 'actual-destination',
          fromAddress: 'actual-source',
          chainTxID: 'a' * 64,
          reviewReason: '审核通过');
    await _pump(tester, api);
    await tester.pumpAndSettle();
    expect(find.text('等待出款'), findsOneWidget);
    expect(_fieldText(tester, 'address').replaceAll('\u200B', ''),
        'actual-destination');
    expect(_fieldText(tester, 'from-address').replaceAll('\u200B', ''),
        'actual-source');
    expect(_fieldText(tester, 'hash').replaceAll('\u200B', ''), 'a' * 64);
    expect(find.byKey(const ValueKey('wallet-journal-open-linked-order-hash')),
        findsOneWidget);
    expect(find.text('审核通过'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

String _fieldText(WidgetTester tester, String field) => tester
    .widget<Text>(
        find.byKey(ValueKey('wallet-journal-detail-linked-order-$field')))
    .data!;

Future<void> _pump(WidgetTester tester, _OrderApi api,
    {bool Function()? isCurrent}) async {
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh', 'CN'),
    supportedLocales: walletRecordLocales,
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: WalletJournalLinkedOrderScreen(
      entry: WalletJournalEntry.fromJson(journalTestJson()),
      api: api,
      isCurrentAccount: isCurrent ?? () => true,
    ),
  ));
  await tester.pump();
}

WalletFundOrder _order({
  String id = 'packet-order',
  String biz = 'packet_normal',
  String status = 'refunded',
}) =>
    WalletFundOrder(
      orderID: id,
      biz: biz,
      currency: FundCurrency.usdt,
      amount: '10',
      status: status,
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(1791244800000, isUtc: true),
    );

class _OrderApi extends WalletFundApi {
  final List<String> requested = [];
  Future<WalletFundOrder> Function(String)? respond;

  @override
  Future<WalletFundOrder> getOrder(String orderID) {
    requested.add(orderID);
    return respond!(orderID);
  }
}
