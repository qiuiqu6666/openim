import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/exchange/data/wallet_swap_quote_controller.dart';
import 'package:openim/pages/wallet/exchange/wallet_exchange_screen.dart';
import 'package:openim/pages/wallet/operations/wallet_operation_detail_screen.dart';
import 'package:openim/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:openim/services/fund_api.dart' show FundApiException;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wallet_operation_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('older input quote cannot replace latest displayed quote',
      (tester) async {
    final api = WalletOperationTestApi();
    final responses = <String, Completer<WalletSwapQuote>>{};
    api.onQuote = (request) {
      final response = Completer<WalletSwapQuote>();
      responses[request['amount'] as String] = response;
      return response.future;
    };
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api)));
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-1')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(responses.keys, ['1']);
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-delete')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-2')));
    await tester.pump(const Duration(milliseconds: 350));
    expect(responses.keys, ['1', '2']);
    responses['2']!.complete(walletSwapTestQuote(
        FundAmount.parse('2', FundCurrency.usdt), FundCurrency.bi99,
        quoteID: 'new-input-quote'));
    await tester.pumpAndSettle();
    expect(find.text('≈ 2.00 USD'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('wallet-swap-output')))
            .data,
        '16.00 99BI');
    responses['1']!.complete(walletSwapTestQuote(
        FundAmount.parse('1', FundCurrency.usdt), FundCurrency.bi99,
        quoteID: 'stale-input-quote'));
    await tester.pumpAndSettle();
    expect(find.text('≈ 2.00 USD'), findsOneWidget);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('wallet-swap-output')))
            .data,
        '16.00 99BI');
    expect(api.writes, isEmpty);
    await disposeWalletOperationPage(tester);
  });

  testWidgets('expired quote requires refresh and cannot settle during PIN',
      (tester) async {
    var now = DateTime.now();
    final api = WalletOperationTestApi()..now = () => now;
    final quotes = WalletSwapQuoteController(
        api: api, isActive: () => true, now: () => now);
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api),
            settingsService: WalletOperationTestSettings(),
            quoteController: quotes));
    await enterWalletSwapAmount(tester, '1.234567');
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('wallet-swap-quote-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wallet-swap-quote-expired')),
        findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    final beforeRefresh = api.quoteRequests.length;
    await tester.tap(find.byKey(const ValueKey('wallet-swap-quote-refresh')));
    await tester.pumpAndSettle();
    expect(api.quoteRequests, hasLength(beforeRefresh + 1));
    expect(
        find.byKey(const ValueKey('wallet-swap-quote-expired')), findsNothing);
    await confirmWalletSwapQuote(tester);
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    now = now.add(const Duration(seconds: 31));
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();
    await enterWalletOperationPin(tester);
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    await disposeWalletOperationPage(tester);
  });

  testWidgets(
      'timeout recovers original client ID and not found keeps write lock',
      (tester) async {
    final api = WalletOperationTestApi();
    api.onSwap = (write) async {
      final quote = api.issuedQuotes[write['quoteID']]!;
      api.lastOrder = WalletFundOrder(
          orderID: 'order-from-accepted-timeout',
          clientOrderID: write['clientOrderID'] as String,
          biz: 'swap',
          currency: quote.fromCurrency,
          amount: quote.amount.decimal,
          status: 'done',
          targetCurrency: quote.toCurrency,
          targetAmount: quote.estimatedReceived.decimal,
          quoteID: quote.quoteID);
      throw const FundApiException(-1, 'timeout', isUncertain: true);
    };
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: operation,
            settingsService: WalletOperationTestSettings()));
    await enterWalletSwapAmount(tester, '1.234567');
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    await confirmWalletSwapQuote(tester);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    final originalWrite = Map<String, dynamic>.from(api.writes.single);
    expect(operation.unresolved, isTrue);
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    api.onOrderByClient =
        (_) async => throw const FundApiException(20032, '订单尚不存在');
    final query = find.byKey(const ValueKey('wallet-operation-query'));
    await tester.ensureVisible(query);
    await tester.pumpAndSettle();
    await tester.tap(query);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(api.queriedClientIDs, [originalWrite['clientOrderID']]);
    expect(operation.draft!.clientOrderID, originalWrite['clientOrderID']);
    expect(operation.draft!.amount.decimal, originalWrite['amount']);
    expect(operation.unresolved, isTrue);
    expect(operation.canSubmit, isFalse);
    expect(api.writes, hasLength(1));
    api.onOrderByClient = null;
    await tester.tap(query);
    await tester.pumpAndSettle();
    expect(api.queriedClientIDs,
        [originalWrite['clientOrderID'], originalWrite['clientOrderID']]);
    expect(find.byType(WalletOperationDetailScreen), findsOneWidget);
    expect(
        tester
            .widget<WalletOperationDetailScreen>(
                find.byType(WalletOperationDetailScreen))
            .receipt
            .order
            .quoteID,
        originalWrite['quoteID']);
    expect(api.writes, [originalWrite]);
    await disposeWalletOperationPage(tester);
  });

  testWidgets(
      'server expired quote returns to preview and needs new confirmation',
      (tester) async {
    final api = WalletOperationTestApi()
      ..onSwap = (_) async => throw const FundApiException(20072, '报价已过期');
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api),
            settingsService: WalletOperationTestSettings()));
    await enterWalletSwapAmount(tester, '1.234567');
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    await confirmWalletSwapQuote(tester);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    final refusedQuoteID = api.writes.single['quoteID'];
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(find.byType(WalletExchangeScreen), findsOneWidget);
    final preview = find.byKey(const ValueKey('wallet-swap-submit'));
    expect(tester.widget<FilledButton>(preview).onPressed, isNotNull);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('wallet-swap-quote-confirm')),
        findsOneWidget);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, hasLength(1));
    await confirmWalletSwapQuote(tester);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(2));
    expect(api.writes.last['quoteID'], isNot(refusedQuoteID));
    expect(api.writes.last['amount'], '1.234567');
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(find.byType(WalletExchangeScreen), findsOneWidget);
    await disposeWalletOperationPage(tester);
  });

  testWidgets(
      'late expired response after payment dismissal leaves swap page open',
      (tester) async {
    final response = Completer<WalletSwapResult>();
    final api = WalletOperationTestApi()..onSwap = (_) => response.future;
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: operation,
            settingsService: WalletOperationTestSettings()));
    await enterWalletSwapAmount(tester, '1.234567');
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    await confirmWalletSwapQuote(tester);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    expect(api.writes, hasLength(1));
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    // The sheet's modal barrier remains dismissible during an in-flight POST.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(find.byType(WalletExchangeScreen), findsOneWidget);
    response.completeError(const FundApiException(20072, '报价已过期'));
    await tester.pumpAndSettle();
    expect(find.byType(WalletExchangeScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('wallet-swap-submit')), findsOneWidget);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, hasLength(1));
    expect(tester.takeException(), isNull);
    await disposeWalletOperationPage(tester);
  });

  testWidgets(
      'late accepted response after payment dismissal refreshes balances',
      (tester) async {
    final response = Completer<WalletSwapResult>();
    final api = WalletOperationTestApi()..onSwap = (_) => response.future;
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: operation,
            settingsService: WalletOperationTestSettings()));
    await enterWalletSwapAmount(tester, '1.234567');
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    await confirmWalletSwapQuote(tester);
    for (final digit in '123456'.split('')) {
      await tester.tap(find.text(digit).last);
      await tester.pump();
    }
    expect(api.writes, hasLength(1));
    final original = api.writes.single;
    final quote = api.issuedQuotes[original['quoteID']]!;
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsNothing);
    final balancesBeforeResponse = api.balanceCalls;
    response.complete(WalletSwapResult(
        order: WalletFundOrder(
            orderID: 'accepted-late-order',
            clientOrderID: original['clientOrderID'] as String,
            biz: 'swap',
            currency: quote.fromCurrency,
            amount: quote.amount.decimal,
            status: 'done',
            targetCurrency: quote.toCurrency,
            targetAmount: quote.estimatedReceived.decimal,
            quoteID: quote.quoteID),
        received: quote.estimatedReceived.decimal));
    await tester.pumpAndSettle();
    expect(find.byType(WalletExchangeScreen), findsOneWidget);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.balanceCalls, balancesBeforeResponse + 1);
    expect(api.writes, [original]);
    expect(operation.draft, isNull);
    expect(operation.receipt, isNull);
    expect(operation.canSubmit, isTrue);
    expect(find.byKey(const ValueKey('wallet-swap-completed')), findsNothing);
    expect(find.textContaining('闪兑成功'), findsWidgets);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await disposeWalletOperationPage(tester);
  });
}

