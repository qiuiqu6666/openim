import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_coordinator.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/exchange/wallet_exchange_screen.dart';
import 'package:openim/pages/wallet/exchange/widgets/wallet_exchange_form.dart';
import 'package:openim/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wallet_operation_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'completed swap accepts another pair with fresh quote and client ID',
      (tester) async {
    final api = WalletOperationTestApi();
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: operation,
            settingsService: WalletOperationTestSettings()));
    await _settle(tester, '1.234567');
    expect(api.writes, hasLength(1));
    final first = Map<String, dynamic>.from(api.writes.single);
    expect(operation.draft, isNull);
    expect(operation.receipt, isNull);
    expect(operation.canSubmit, isTrue);
    expect(_form(tester).amountController.text, isEmpty);
    expect(find.byKey(const ValueKey('wallet-swap-completed')), findsNothing);
    expect(
        tester
            .widget<DropdownButton<FundCurrency>>(
                find.byKey(const ValueKey('wallet-swap-from')))
            .onChanged,
        isNotNull);
    // A second tap while the amount is empty cannot replay the previous POST.
    final preview = find.byKey(const ValueKey('wallet-swap-submit'));
    expect(tester.widget<FilledButton>(preview).onPressed, isNull);
    await tester.tap(preview, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.writes, [first]);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-5')));
    await tester.pump();
    expect(_form(tester).amountController.text, '5');
    await selectWalletSwapCurrency(
        tester, 'wallet-swap-from', FundCurrency.trx);
    await selectWalletSwapCurrency(tester, 'wallet-swap-to', FundCurrency.usdt);
    expect(_form(tester).amountController.text, isEmpty);
    await enterWalletSwapAmount(tester, '2.345678');
    expect(_form(tester).amountController.text, '2.345678');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    expect(api.writes, [first]);
    await confirmWalletSwapQuote(tester);
    expect(api.writes, [first]);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(2));
    final second = api.writes.last;
    expect(first['currency'], 'USDT');
    expect(first['amount'], '1.234567');
    expect(second['currency'], 'TRX');
    expect(second['toCurrency'], 'USDT');
    expect(second['amount'], '2.345678');
    expect(second['clientOrderID'], isNot(first['clientOrderID']));
    expect(second['quoteID'], isNot(first['quoteID']));
    final reviewed = api.issuedQuotes[second['quoteID']]!;
    expect(reviewed.amount, FundAmount.parse('2.345678', FundCurrency.trx));
    expect(reviewed.toCurrency, FundCurrency.usdt);
    expect(operation.draft, isNull);
    expect(operation.receipt, isNull);
    expect(_form(tester).amountController.text, isEmpty);
    expect(tester.takeException(), isNull);
    await disposeWalletOperationPage(tester);
  });

  for (final status in ['done', 'open']) {
    testWidgets('restored terminal marker is checked against server $status',
        (tester) async {
      final api = WalletOperationTestApi();
      final operation = testWalletOperation(WalletOperationKind.swap, api);
      final quote = walletSwapTestQuote(
          FundAmount.parse('1.234567', FundCurrency.usdt), FundCurrency.bi99,
          quoteID: 'saved-quote');
      await operation.store.save(WalletOperationDraft(
          kind: WalletOperationKind.swap,
          clientOrderID: 'saved-client',
          amount: quote.amount,
          toCurrency: quote.toCurrency,
          quoteID: quote.quoteID,
          expectedReceived: quote.estimatedReceived.decimal,
          orderID: 'saved-server-order',
          submitted: true,
          terminal: true));
      api.lastOrder = WalletFundOrder(
          orderID: 'saved-server-order',
          clientOrderID: 'saved-client',
          biz: 'swap',
          currency: quote.fromCurrency,
          amount: quote.amount.decimal,
          targetCurrency: quote.toCurrency,
          targetAmount: quote.estimatedReceived.decimal,
          quoteID: quote.quoteID,
          status: status);
      await pumpWalletOperation(
          tester,
          WalletExchangeScreen(
              coordinator: operation,
              settingsService: WalletOperationTestSettings()));
      expect(api.queriedIDs, ['saved-server-order']);
      expect(api.writes, isEmpty);
      if (status == 'done') {
        expect(operation.draft, isNull);
        expect(operation.canSubmit, isTrue);
        expect(_form(tester).amountController.text, isEmpty);
        expect(
            find.byKey(const ValueKey('wallet-swap-completed')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('wallet-swap-key-7')));
        await tester.pump();
        expect(_form(tester).amountController.text, '7');
      } else {
        expect(operation.unresolved, isTrue);
        expect(operation.canSubmit, isFalse);
        expect(operation.draft!.clientOrderID, 'saved-client');
        await tester.tap(find.byKey(const ValueKey('wallet-swap-key-7')),
            warnIfMissed: false);
        await tester.pump();
        expect(_form(tester).amountController.text, '1.234567');
        expect(
            tester
                .widget<FilledButton>(
                    find.byKey(const ValueKey('wallet-swap-submit')))
                .onPressed,
            isNull);
      }
      expect(api.writes, isEmpty);
      expect(tester.takeException(), isNull);
      await disposeWalletOperationPage(tester);
    });
  }

  testWidgets('account change cannot submit or edit after a completed swap',
      (tester) async {
    var active = true;
    final api = WalletOperationTestApi();
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api,
                isCurrent: () => active),
            settingsService: WalletOperationTestSettings()));
    await _settle(tester, '1.234567');
    await enterWalletSwapAmount(tester, '2.345678');
    final before = api.quoteRequests.length;
    active = false;
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-7')));
    await tester.pump();
    expect(_form(tester).amountController.text, '2.345678');
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    expect(api.quoteRequests, hasLength(before));
    expect(api.writes, hasLength(1));
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(
        find.byKey(const ValueKey('wallet-swap-quote-confirm')), findsNothing);
    await disposeWalletOperationPage(tester);
  });

  testWidgets('completed storage failure continues safely without another POST',
      (tester) async {
    final api = WalletOperationTestApi();
    final recovery = Completer<void>();
    final store = _FailTerminalStore(recovery.future);
    final operation = WalletOperationCoordinator(
        kind: WalletOperationKind.swap,
        api: api,
        store: store,
        serverURL: 'https://wallet.test/',
        accountID: 'fixture-user',
        isAccountCurrent: () => true);
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: operation,
            settingsService: WalletOperationTestSettings()));
    await _settle(tester, '1.234567');
    expect(store.terminalSaves, 2);
    expect(api.writes, hasLength(1));
    expect(operation.receipt!.accepted, isTrue);
    expect(operation.draft, isNotNull);
    expect(_form(tester).amountController.text, '1.234567');
    final continueButton = find.byKey(const ValueKey('wallet-swap-submit'));
    expect(find.descendant(of: continueButton, matching: find.text('继续闪兑')),
        findsOneWidget);
    expect(tester.widget<FilledButton>(continueButton).onPressed, isNotNull);
    await tester.ensureVisible(continueButton);
    await tester.tap(continueButton);
    // A repeated tap before the first cleanup completes must not submit funds.
    await tester.tap(continueButton);
    expect(api.writes, hasLength(1));
    expect(operation.draft, isNotNull);
    recovery.complete();
    await tester.pumpAndSettle();
    expect(store.terminalSaves, 3);
    expect(api.writes, hasLength(1));
    expect(operation.draft, isNull);
    expect(operation.receipt, isNull);
    expect(_form(tester).amountController.text, isEmpty);
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-4')));
    await tester.pump();
    expect(_form(tester).amountController.text, '4');
    expect(api.writes, hasLength(1));
    await disposeWalletOperationPage(tester);
  });

  testWidgets('successful PIN shows payment success instead of its keypad',
      (tester) async {
    final api = WalletOperationTestApi();
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api),
            settingsService: WalletOperationTestSettings()));
    await enterWalletSwapAmount(tester, '1.234567');
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    await confirmWalletSwapQuote(tester);
    late DateTime sentAt;
    for (final digit in '123456'.split('')) {
      await tester.tap(find.text(digit).last);
      if (digit == '6') sentAt = tester.binding.clock.now();
      await tester.pump();
    }
    await tester.pumpAndSettle();
    final payment = find.byType(PayPasswordPrompt);
    expect(payment, findsOneWidget);
    expect(find.descendant(of: payment, matching: find.text('支付成功')),
        findsOneWidget);
    expect(
        find.descendant(of: payment, matching: find.text('1')), findsNothing);
    expect(find.descendant(of: payment, matching: find.text('正在验证...')),
        findsNothing);
    expect(api.writes, hasLength(1));
    final elapsed = tester.binding.clock.now().difference(sentAt);
    expect(elapsed, lessThan(const Duration(milliseconds: 800)));
    await tester.pump(const Duration(milliseconds: 800) - elapsed);
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    // The leaving payment route is still mounted at 900 ms. Its delayed
    // success must not pop the swap page while the exit animation runs.
    await tester.pump(const Duration(milliseconds: 100));
    expect(payment, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(payment, findsNothing);
    expect(find.byType(WalletExchangeScreen), findsOneWidget);
    expect(_form(tester).amountController.text, isEmpty);
    expect(find.byKey(const ValueKey('wallet-swap-completed')), findsNothing);
    expect(api.writes, hasLength(1));
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-7')));
    await tester.pump();
    expect(_form(tester).amountController.text, '7');
    await disposeWalletOperationPage(tester);
  });
}

class _FailTerminalStore extends WalletOperationPendingStore {
  _FailTerminalStore(this.recovery)
      : super(accountKey: 'https://wallet.test:fixture-user');
  final Future<void> recovery;
  int terminalSaves = 0;
  @override
  Future<void> save(WalletOperationDraft draft) async {
    if (draft.terminal && ++terminalSaves <= 2) {
      throw StateError('fixture terminal storage failure');
    }
    if (draft.terminal && terminalSaves == 3) await recovery;
    await super.save(draft);
  }
}

WalletExchangeForm _form(WidgetTester tester) =>
    tester.widget<WalletExchangeForm>(find.byType(WalletExchangeForm));

Future<void> _settle(WidgetTester tester, String amount) async {
  await enterWalletSwapAmount(tester, amount);
  final preview = find.byKey(const ValueKey('wallet-swap-submit'));
  await tester.ensureVisible(preview);
  await tester.tap(preview);
  await tester.pumpAndSettle();
  await confirmWalletSwapQuote(tester);
  await enterWalletOperationPin(tester);
}
