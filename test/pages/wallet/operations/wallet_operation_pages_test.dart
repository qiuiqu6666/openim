import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/exchange/wallet_exchange_screen.dart';
import 'package:openim/pages/wallet/exchange/widgets/wallet_exchange_form.dart';
import 'package:openim/pages/wallet/withdraw_chain_review_screen.dart';
import 'package:openim/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:openim/services/fund_api.dart' show FundApiException;
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wallet_operation_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final currency in [FundCurrency.usdt, FundCurrency.trx]) {
    testWidgets(
        '${currency.code} withdrawal shows total debit then returns to editable amount',
        (tester) async {
      final api = WalletOperationTestApi();
      api.onWithdraw = (write) async {
        final order = WalletFundOrder(
          orderID: 'accepted-withdrawal',
          clientOrderID: write['clientOrderID'] as String,
          biz: 'withdraw',
          currency: currency,
          amount: write['amount'] as String,
          status: 'withdraw_pending',
          toAddress: walletOperationTestAddress,
          fee: '0.25',
        );
        api.lastOrder = order;
        return WalletWithdrawResult(order: order, fee: '0.25');
      };
      final settings = WalletOperationTestSettings();
      final operation = testWalletOperation(WalletOperationKind.withdraw, api);
      await pumpWalletOperation(
          tester,
          Builder(
              builder: (context) => Scaffold(
                  body: FilledButton(
                      onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                              builder: (_) => WithdrawChainReviewScreen(
                                  coin: withdrawalTestCoin(currency),
                                  payMethod: withdrawalTestMethod(currency),
                                  toAddress: walletOperationTestAddress,
                                  amountMinor: 1123456,
                                  coordinator: operation,
                                  securityAuthorizer:
                                      approveWalletSecurityForTest,
                                  settingsService: settings))),
                      child: const Text('编辑提现数量')))));
      await tester.tap(find.text('编辑提现数量'));
      await tester.pumpAndSettle();
      expect(find.text('手续费：0.25 ${currency.code}'), findsOneWidget);
      expect(find.textContaining('0 fee'), findsNothing);
      await tester
          .ensureVisible(find.byKey(const ValueKey('wallet-withdraw-confirm')));
      await tester.tap(find.byKey(const ValueKey('wallet-withdraw-confirm')));
      await tester.pumpAndSettle();
      expect(settings.statusCalls, 1);
      expect(find.byType(PayPasswordPrompt), findsOneWidget);
      final prompt =
          tester.widget<PayPasswordPrompt>(find.byType(PayPasswordPrompt));
      expect(prompt.amountText, '1.373456');
      expect(prompt.amountCoin, currency.displayName);
      await enterWalletOperationPin(tester);
      expect(api.writes, hasLength(1));
      expect(api.writes.single['amount'], '1.123456');
      expect(api.writes.single['currency'], currency.code);
      expect(api.lastOrder!.fee, '0.25');
      expect(api.lastOrder!.status, 'withdraw_pending');
      expect(operation.draft, isNull);
      expect(operation.receipt, isNull);
      expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
      expect(find.byType(WithdrawChainReviewScreen), findsNothing);
      expect(find.text('编辑提现数量'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('wallet-operation-status')), findsNothing);
      expect(find.textContaining('业务单号：'), findsNothing);
    });
  }

  for (final from in FundCurrency.values) {
    for (final to in FundCurrency.values.where((coin) => coin != from)) {
      testWidgets(
          'currency pickers expose ${from.code} -> ${to.code} and submit exact wire currency',
          (tester) async {
        final api = WalletOperationTestApi();
        final operation = testWalletOperation(WalletOperationKind.swap, api);
        await pumpWalletOperation(
            tester,
            WalletExchangeScreen(
                coordinator: operation,
                settingsService: WalletOperationTestSettings()));
        await selectWalletSwapCurrency(tester, 'wallet-swap-from', from);
        await selectWalletSwapCurrency(tester, 'wallet-swap-to', to);
        final form =
            tester.widget<WalletExchangeForm>(find.byType(WalletExchangeForm));
        expect(form.from, from);
        expect(form.to, to);
        final fromPicker = tester.widget<DropdownButton<FundCurrency>>(
            find.byKey(const ValueKey('wallet-swap-from')));
        final toPicker = tester.widget<DropdownButton<FundCurrency>>(
            find.byKey(const ValueKey('wallet-swap-to')));
        expect(fromPicker.items!.map((item) => item.value).toList(),
            FundCurrency.values);
        expect(toPicker.items!.map((item) => item.value).toList(),
            FundCurrency.values);
        final amount = from == FundCurrency.bi99 ? '1.23' : '1.234567';
        await enterWalletSwapAmount(tester, amount);
        expect(form.amountController.text, amount);
        expect(api.quoteRequests.last['amount'], amount);
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('wallet-swap-output')))
                .data,
            matches(RegExp('^\\d+\\.\\d{2} ${to.displayName}\$')));
        await tester
            .ensureVisible(find.byKey(const ValueKey('wallet-swap-submit')));
        await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
        await tester.pumpAndSettle();
        expect(api.writes, isEmpty);
        expect(find.byType(PayPasswordPrompt), findsNothing);
        await confirmWalletSwapQuote(tester);
        expect(find.byType(PayPasswordPrompt), findsOneWidget);
        expect(
            tester
                .widget<PayPasswordPrompt>(find.byType(PayPasswordPrompt))
                .amountText,
            '1.23');
        await enterWalletOperationPin(tester);
        expect(api.writes.single['currency'], from.code);
        expect(api.writes.single['toCurrency'], to.code);
        expect(api.writes.single['amount'], amount);
        final confirmedQuote =
            api.issuedQuotes[api.writes.single['quoteID'] as String]!;
        expect(confirmedQuote.amount, FundAmount.parse(amount, from));
        expect(confirmedQuote.toCurrency, to);
        expect(operation.draft, isNull);
        expect(operation.receipt, isNull);
        expect(form.amountController.text, isEmpty);
        expect(
            find.byKey(const ValueKey('wallet-swap-completed')), findsNothing);
        expect(find.byKey(const ValueKey('wallet-swap-completed-query')),
            findsNothing);
        expect(tester.takeException(), isNull);
        await disposeWalletOperationPage(tester);
      });
    }
  }

  testWidgets('currency quantities and right arrows open their real picker',
      (tester) async {
    final api = WalletOperationTestApi();
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api)));
    await tester.tap(find.byKey(const ValueKey('wallet-swap-available')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(FundCurrency.trx.displayName).last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<DropdownButton<FundCurrency>>(
                find.byKey(const ValueKey('wallet-swap-from')))
            .value,
        FundCurrency.trx);
    for (final entry in [
      ('wallet-swap-from', FundCurrency.usdt),
      ('wallet-swap-to', FundCurrency.trx)
    ]) {
      final picker = find.byKey(ValueKey(entry.$1));
      await tester.tap(find
          .descendant(
              of: picker, matching: find.byIcon(Icons.chevron_right_rounded))
          .last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.$2.displayName).last);
      await tester.pumpAndSettle();
      expect(
          tester.widget<DropdownButton<FundCurrency>>(picker).value, entry.$2);
    }
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
  });

  testWidgets(
      'swap keypad limits precision, deletes and clears on pair changes',
      (tester) async {
    final api = WalletOperationTestApi();
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api)));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('≈0.00 USD'), findsOneWidget);
    await enterWalletSwapAmount(tester, '12..3456789');
    WalletExchangeForm form() =>
        tester.widget<WalletExchangeForm>(find.byType(WalletExchangeForm));
    expect(form().amountController.text, '12.345678');
    expect(find.text('≈ 12.34 USD'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-delete')));
    await tester.pump();
    expect(form().amountController.text, '12.34567');
    await selectWalletSwapCurrency(
        tester, 'wallet-swap-from', FundCurrency.bi99);
    expect(form().amountController.text, isEmpty);
    expect(form().to, FundCurrency.usdt);
    await enterWalletSwapAmount(tester, '2.349');
    expect(form().amountController.text, '2.34');
    await tester
        .ensureVisible(find.byKey(const ValueKey('wallet-swap-reverse')));
    await tester.tap(find.byKey(const ValueKey('wallet-swap-reverse')));
    await tester.pumpAndSettle();
    expect(form().from, FundCurrency.usdt);
    expect(form().to, FundCurrency.bi99);
    expect(form().amountController.text, isEmpty);
    expect(api.writes, isEmpty);
  });

  testWidgets('uncertain swap cannot rePOST through PIN, preview or reopening',
      (tester) async {
    final api = WalletOperationTestApi();
    api.onSwap = (_) =>
        Future.error(const FundApiException(-1, 'timeout', isUncertain: true));
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    final settings = WalletOperationTestSettings();
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: operation, settingsService: settings));
    await enterWalletSwapAmount(tester, '1.23');
    await tester
        .ensureVisible(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
    await tester.pumpAndSettle();
    await confirmWalletSwapQuote(tester);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    expect(operation.unresolved, isTrue);
    final originalID = operation.draft!.clientOrderID;
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(1));
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('wallet-swap-submit'));
    expect(api.queriedIDs, isEmpty);
    expect(tester.widget<FilledButton>(preview).onPressed, isNull);
    await tester.ensureVisible(preview);
    await tester.tap(preview, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
    final restored = testWalletOperation(WalletOperationKind.swap, api);
    await pumpWalletOperation(tester,
        WalletExchangeScreen(coordinator: restored, settingsService: settings));
    expect(restored.draft!.clientOrderID, originalID);
    expect(restored.unresolved, isTrue);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-swap-submit')))
            .onPressed,
        isNull);
    expect(api.writes, hasLength(1));
    expect(api.queriedIDs, isEmpty);
    await disposeWalletOperationPage(tester);
  });

  testWidgets('long swap quantity stays readable and deletes exact final digit',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      final api = WalletOperationTestApi();
      await pumpWalletOperation(
          tester,
          WalletExchangeScreen(
              coordinator: testWalletOperation(WalletOperationKind.swap, api)),
          size: const Size(320, 844));
      const amount = '1234567890123456789.123456';
      await enterWalletSwapAmount(tester, amount);
      final form =
          tester.widget<WalletExchangeForm>(find.byType(WalletExchangeForm));
      expect(form.amountController.text, amount);
      expect(find.text('左右滑动查看完整数量'), findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.byKey(const ValueKey('wallet-swap-amount-text')))
              .data,
          amount);
      expect(
          tester
              .getSemantics(find.byKey(const ValueKey('wallet-swap-amount')))
              .getSemanticsData()
              .value,
          '$amount USDT');
      final amountScroll =
          find.byKey(const ValueKey('wallet-swap-amount-scroll'));
      await tester.ensureVisible(amountScroll);
      await tester.pumpAndSettle();
      final scroll = tester.state<ScrollableState>(
          find.descendant(of: amountScroll, matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final atEnd = scroll.position.pixels;
      await tester.drag(amountScroll, const Offset(160, 0));
      await tester.pumpAndSettle();
      final towardsStart = scroll.position.pixels;
      expect(towardsStart, lessThan(atEnd));
      await tester.drag(amountScroll, const Offset(-160, 0));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(towardsStart));
      await tester.tap(find.byKey(const ValueKey('wallet-swap-key-delete')));
      await tester.pumpAndSettle();
      expect(form.amountController.text, '1234567890123456789.12345');
      expect(tester.takeException(), isNull);
      expect(api.writes, isEmpty);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
      'quantity over available balance disables preview until corrected',
      (tester) async {
    final api = WalletOperationTestApi();
    await pumpWalletOperation(
        tester,
        WalletExchangeScreen(
            coordinator: testWalletOperation(WalletOperationKind.swap, api)));
    await enterWalletSwapAmount(tester, '100.000001');
    final validation = find.byKey(const ValueKey('wallet-swap-validation'));
    final preview = find.byKey(const ValueKey('wallet-swap-submit'));
    expect(tester.widget<Text>(validation).data, '余额不足');
    expect(tester.widget<FilledButton>(preview).onPressed, isNull);
    await tester.tap(preview, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(api.writes, isEmpty);
    await tester.tap(find.byKey(const ValueKey('wallet-swap-key-delete')));
    await tester.pumpAndSettle();
    expect(validation, findsNothing);
    expect(tester.widget<FilledButton>(preview).onPressed, isNotNull);
    await disposeWalletOperationPage(tester);
  });

  for (final brightness in Brightness.values) {
    for (final size in [const Size(320, 844), const Size(844, 390)]) {
      testWidgets(
          'swap keypad remains reachable in ${size.width}x${size.height} large text ${brightness.name}',
          (tester) async {
        final api = WalletOperationTestApi();
        await pumpWalletOperation(
            tester,
            WalletExchangeScreen(
                coordinator:
                    testWalletOperation(WalletOperationKind.swap, api)),
            brightness: brightness,
            size: size,
            textScale: 2);
        await enterWalletSwapAmount(tester, '1.23');
        await tester
            .ensureVisible(find.byKey(const ValueKey('wallet-swap-submit')));
        expect(tester.takeException(), isNull);
        expect(api.writes, isEmpty);
        await disposeWalletOperationPage(tester);
      });
    }
  }
}
