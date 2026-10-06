import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/fund/withdrawal_security/withdrawal_security.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_coordinator.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/withdrawal/withdraw_chain_review_screen.dart';
import 'package:openim/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:openim/services/fund_api.dart' show FundApiException;
import 'package:shared_preferences/shared_preferences.dart';

import '../operations/support/wallet_operation_test_support.dart';

/// Policy responses are test fixtures only; these tests never contact a server.
class _PolicyApi extends WalletOperationTestApi {
  WalletCurrencyRule? rule = WalletCurrencyRule(
    currency: FundCurrency.usdt,
    minWithdrawAmount: '10',
    withdrawFee: '1.000001',
    withdrawFeeCurrency: FundCurrency.usdt,
  );
  String available = '100';
  int rulesCalls = 0;
  Future<WalletDepositAddress> Function()? onRules;

  WalletDepositAddress response() => WalletDepositAddress(
        status: 'ready',
        network: 'TRON',
        address: walletOperationTestAddress,
        currencies: const [FundCurrency.usdt, FundCurrency.trx],
        confirmations: 19,
        usdtContract: 'fixture-contract',
        currencyRules: rule == null ? const {} : {rule!.currency: rule!},
      );

  @override
  Future<WalletDepositAddress> fetchDepositAddress() async {
    rulesCalls++;
    return onRules == null ? response() : await onRules!();
  }

  @override
  Future<List<FundBalance>> fetchBalances() async => FundCurrency.values
      .map((currency) => FundBalance(
            currency: currency,
            available: FundAmount.parse(
                currency == FundCurrency.bi99 ? '100' : available, currency),
            frozen: FundAmount.zero(currency),
          ))
      .toList();
}

WithdrawChainReviewScreen _page(_PolicyApi api,
        {int amountMinor = 12345678,
        WalletOperationTestSettings? settings,
        WalletOperationCoordinator? coordinator,
        Future<FundSecurityProof?> Function(
                BuildContext context, FundSecurityRequest request)?
            securityAuthorizer,
        bool Function()? isCurrent,
        String accountID = 'withdraw-rule-user'}) =>
    WithdrawChainReviewScreen(
      coin: withdrawalTestCoin(FundCurrency.usdt),
      payMethod: withdrawalTestMethod(FundCurrency.usdt),
      toAddress: walletOperationTestAddress,
      amountMinor: amountMinor,
      coordinator: coordinator ??
          testWalletOperation(WalletOperationKind.withdraw, api,
              accountID: accountID, isCurrent: isCurrent),
      settingsService: settings ?? WalletOperationTestSettings(),
      securityAuthorizer: securityAuthorizer ?? approveWalletSecurityForTest,
    );

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

Future<void> _confirm(WidgetTester tester, {bool settle = true}) async {
  final button = find.byKey(const ValueKey('wallet-withdraw-confirm'));
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
  await tester.tap(button);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('review displays total debit and submits only the principal',
      (tester) async {
    final api = _PolicyApi();
    await pumpWalletOperation(tester, _page(api));
    expect(_text(tester, 'wallet-withdraw-minimum'), '最低提现：10 USDT');
    expect(_text(tester, 'wallet-withdraw-fee'), '手续费：1.000001 USDT');
    expect(_text(tester, 'wallet-withdraw-total-debit'), '总扣款：13.345679 USDT');
    expect(api.rulesCalls, 1);
    await _confirm(tester);
    expect(api.rulesCalls, 2);
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    final prompt =
        tester.widget<PayPasswordPrompt>(find.byType(PayPasswordPrompt));
    expect(prompt.amountText, '13.345679');
    expect(prompt.amountCoin, 'USDT');
    await enterWalletOperationPin(tester);
    expect(api.writes.single['amount'], '12.345678');
    expect(api.lastOrder!.fee, '0.25');
    expect(find.byKey(const ValueKey('wallet-operation-status')), findsNothing);
    expect(find.textContaining('业务单号：'), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNotNull);
  });

  testWidgets('minimum blocks a new withdrawal before payment auth',
      (tester) async {
    final api = _PolicyApi();
    final settings = WalletOperationTestSettings();
    await pumpWalletOperation(
        tester, _page(api, amountMinor: 9999999, settings: settings));
    expect(_text(tester, 'wallet-withdraw-validation'), '提现金额不能低于 10 USDT');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNull);
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
  });

  testWidgets('principal can fit while principal plus fee exceeds balance',
      (tester) async {
    final api = _PolicyApi()..available = '12.345678';
    await pumpWalletOperation(tester, _page(api));
    expect(_text(tester, 'wallet-withdraw-validation'), '可用余额不足以支付提现金额和手续费');
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNull);
    expect(api.writes, isEmpty);
  });

  testWidgets('explicit zero fee is usable and does not invent an extra debit',
      (tester) async {
    final api = _PolicyApi()
      ..available = '12.345678'
      ..rule = WalletCurrencyRule(
        currency: FundCurrency.usdt,
        minWithdrawAmount: '0',
        withdrawFee: '0',
        withdrawFeeCurrency: FundCurrency.usdt,
      );
    await pumpWalletOperation(tester, _page(api));
    expect(_text(tester, 'wallet-withdraw-fee'), '手续费：0 USDT');
    expect(_text(tester, 'wallet-withdraw-total-debit'), '总扣款：12.345678 USDT');
    await _confirm(tester);
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    final prompt =
        tester.widget<PayPasswordPrompt>(find.byType(PayPasswordPrompt));
    expect(prompt.amountText, '12.345678',
        reason: 'An explicit zero fee leaves the displayed total unchanged');
    expect(api.writes, isEmpty);
    await enterWalletOperationPin(tester);
    expect(api.writes.single['amount'], '12.345678');
  });

  testWidgets('missing policy blocks new payment and explicit retry recovers',
      (tester) async {
    final api = _PolicyApi()..rule = null;
    await pumpWalletOperation(tester, _page(api));
    expect(_text(tester, 'wallet-withdraw-fee'), '手续费：暂未提供');
    expect(_text(tester, 'wallet-withdraw-total-debit'), '总扣款：暂未提供');
    expect(_text(tester, 'wallet-withdraw-validation'), '提现规则暂不可用，请重试');
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNull);
    api.rule = WalletCurrencyRule(
      currency: FundCurrency.usdt,
      minWithdrawAmount: '1',
      withdrawFee: '0.1',
      withdrawFeeCurrency: FundCurrency.usdt,
    );
    final retry = find.byKey(const ValueKey('wallet-withdraw-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('wallet-withdraw-validation')), findsNothing);
    expect(api.rulesCalls, 2);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNotNull);
    expect(api.writes, isEmpty);
  });

  for (final missing in ['minimum', 'fee', 'feeCurrency']) {
    testWidgets('a missing $missing never becomes a usable zero policy',
        (tester) async {
      final api = _PolicyApi()
        ..rule = WalletCurrencyRule(
          currency: FundCurrency.usdt,
          minWithdrawAmount: missing == 'minimum' ? null : '0',
          withdrawFee: missing == 'fee' ? null : '0',
          withdrawFeeCurrency:
              missing == 'feeCurrency' ? null : FundCurrency.usdt,
        );
      await pumpWalletOperation(tester, _page(api));
      expect(_text(tester, 'wallet-withdraw-validation'), '提现规则暂不可用，请重试');
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const ValueKey('wallet-withdraw-confirm')))
              .onPressed,
          isNull);
      if (missing != 'minimum') {
        expect(_text(tester, 'wallet-withdraw-fee'), '手续费：暂未提供');
        expect(_text(tester, 'wallet-withdraw-total-debit'), '总扣款：暂未提供');
      }
      expect(find.byType(PayPasswordPrompt), findsNothing);
      expect(api.writes, isEmpty);
    });
  }

  testWidgets('fresh available balance includes fee before opening auth',
      (tester) async {
    final api = _PolicyApi();
    final settings = WalletOperationTestSettings();
    await pumpWalletOperation(tester, _page(api, settings: settings));
    api.available = '12.345678';
    await _confirm(tester);
    expect(_text(tester, 'wallet-withdraw-validation'), '可用余额不足以支付提现金额和手续费');
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
  });

  for (final changeMinimum in [true, false]) {
    testWidgets(
        'fresh ${changeMinimum ? 'minimum' : 'fee'} blocks auth when policy changes',
        (tester) async {
      final api = _PolicyApi();
      final settings = WalletOperationTestSettings();
      await pumpWalletOperation(tester, _page(api, settings: settings));
      api.rule = WalletCurrencyRule(
        currency: FundCurrency.usdt,
        minWithdrawAmount: changeMinimum ? '20' : '10',
        withdrawFee: changeMinimum ? '1' : '100',
        withdrawFeeCurrency: FundCurrency.usdt,
      );
      await _confirm(tester);
      expect(api.rulesCalls, 2);
      expect(settings.statusCalls, 0);
      expect(find.byType(PayPasswordPrompt), findsNothing);
      expect(api.writes, isEmpty);
      expect(_text(tester, 'wallet-withdraw-validation'),
          changeMinimum ? '提现金额不能低于 20 USDT' : '可用余额不足以支付提现金额和手续费');
    });
  }

  testWidgets('account switch during rules refresh cannot open auth or submit',
      (tester) async {
    var current = true;
    final api = _PolicyApi();
    final settings = WalletOperationTestSettings();
    await pumpWalletOperation(
        tester, _page(api, settings: settings, isCurrent: () => current));
    final completer = Completer<WalletDepositAddress>();
    api.onRules = () => completer.future;
    await _confirm(tester, settle: false);
    current = false;
    completer.complete(api.response());
    await tester.pumpAndSettle();
    expect(settings.statusCalls, 0);
    expect(api.writes, isEmpty);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposed review ignores an outstanding policy refresh',
      (tester) async {
    final api = _PolicyApi();
    await pumpWalletOperation(tester, _page(api));
    final completer = Completer<WalletDepositAddress>();
    api.onRules = () => completer.future;
    await _confirm(tester, settle: false);
    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete(api.response());
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid confirmation refreshes once and opens only one auth sheet',
      (tester) async {
    final api = _PolicyApi();
    final settings = WalletOperationTestSettings();
    await pumpWalletOperation(tester, _page(api, settings: settings));
    final callback = tester
        .widget<FilledButton>(
            find.byKey(const ValueKey('wallet-withdraw-confirm')))
        .onPressed!;
    final completer = Completer<WalletDepositAddress>();
    api.onRules = () => completer.future;
    callback();
    callback();
    await tester.pump();
    expect(api.rulesCalls, 2);
    completer.complete(api.response());
    await tester.pumpAndSettle();
    expect(settings.statusCalls, 1);
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    expect(api.writes, isEmpty);
  });

  testWidgets('cancelled security clears only its unsubmitted draft',
      (tester) async {
    final api = _PolicyApi();
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    final verifiedIDs = <String>[];
    await pumpWalletOperation(
        tester,
        _page(api, coordinator: operation,
            securityAuthorizer: (_, request) async {
          verifiedIDs.add(request.fields['clientOrderID']!);
          return verifiedIDs.length == 1 ? null : const FundSecurityProof();
        }));
    await _confirm(tester);
    expect(api.writes, isEmpty);
    expect(operation.draft, isNull);
    expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
    expect(find.byType(PayPasswordPrompt), findsNothing);
    expect(find.byKey(const ValueKey('wallet-operation-status')), findsNothing);
    await _confirm(tester);
    expect(verifiedIDs, hasLength(2));
    expect(verifiedIDs[1], isNot(verifiedIDs[0]));
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(operation.draft, isNull);
    expect(api.writes, isEmpty);
  });

  testWidgets('explicit refusal keeps PIN retries then releases draft on close',
      (tester) async {
    final api = _PolicyApi()
      ..onWithdraw = (_) =>
          Future.error(const FundApiException(20078, 'fixture wrong code'));
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    await pumpWalletOperation(tester, _page(api, coordinator: operation));
    await _confirm(tester);
    final originalID = operation.draft!.clientOrderID;
    await enterWalletOperationPin(tester);
    expect(operation.draft!.submitted, isFalse);
    expect(operation.draft!.clientOrderID, originalID);
    expect(find.byType(PayPasswordPrompt), findsOneWidget);
    await enterWalletOperationPin(tester);
    expect(api.writes, hasLength(2));
    expect(api.writes.map((write) => write['clientOrderID']),
        everyElement(originalID));
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(operation.draft, isNull);
    expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
    expect(find.byKey(const ValueKey('wallet-operation-status')), findsNothing);
    expect(find.textContaining('业务单号：'), findsNothing);
    await _confirm(tester);
    expect(operation.draft!.clientOrderID, isNot(originalID));
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(operation.draft, isNull);
    expect(api.writes, hasLength(2));
  });

  testWidgets(
      'unknown withdrawal only queries the original order until resolved',
      (tester) async {
    final api = _PolicyApi()
      ..onWithdraw = (_) => Future.error(
          const FundApiException(-1, 'fixture timeout', isUncertain: true));
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    await pumpWalletOperation(tester, _page(api, coordinator: operation));
    await _confirm(tester);
    final original = operation.draft!;
    await enterWalletOperationPin(tester);
    await tester.tap(find.descendant(
        of: find.byType(PayPasswordPrompt),
        matching: find.byIcon(Icons.close_rounded)));
    await tester.pumpAndSettle();
    expect(operation.unresolved, isTrue);
    expect(operation.draft!.clientOrderID, original.clientOrderID);
    expect(find.byKey(const ValueKey('wallet-operation-status')), findsNothing);
    expect(find.textContaining('业务单号：'), findsNothing);
    expect(find.byKey(const ValueKey('wallet-operation-new')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNull);
    final query = find.byKey(const ValueKey('wallet-operation-query'));
    await tester.ensureVisible(query);
    await tester.tap(query);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(api.queriedClientIDs, [original.clientOrderID]);
    expect(operation.draft!.clientOrderID, original.clientOrderID);
    api.lastOrder = WalletFundOrder(
      orderID: 'recovered-server-order',
      clientOrderID: original.clientOrderID,
      biz: 'withdraw',
      currency: original.amount.currency,
      amount: original.amount.decimal,
      status: 'withdraw_pending',
      toAddress: original.toAddress,
      fee: '0.25',
    );
    await tester.tap(query);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(
        api.queriedClientIDs, [original.clientOrderID, original.clientOrderID]);
    expect(api.writes, hasLength(1));
    expect(operation.draft, isNull);
    expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
    expect(find.byKey(const ValueKey('wallet-operation-query')), findsNothing);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNotNull);
  });

  testWidgets('late confirmed query does not pop or toast over a newer route',
      (tester) async {
    final api = _PolicyApi();
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    final original = WalletOperationDraft(
      kind: WalletOperationKind.withdraw,
      clientOrderID: 'covered-original-withdrawal',
      amount: FundAmount.parse('12.345678', FundCurrency.usdt),
      toAddress: walletOperationTestAddress,
      submitted: true,
    );
    await operation.store.save(original);
    final completer = Completer<WalletFundOrder>();
    api.onOrderByClient = (_) => completer.future;
    await pumpWalletOperation(tester, _page(api, coordinator: operation));
    final navigator =
        Navigator.of(tester.element(find.byType(WithdrawChainReviewScreen)));
    final query = find.byKey(const ValueKey('wallet-operation-query'));
    await tester.ensureVisible(query);
    await tester.tap(query);
    await tester.pump();
    expect(api.queriedClientIDs, [original.clientOrderID]);
    navigator.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('新的页面'))));
    await tester.pumpAndSettle();
    completer.complete(WalletFundOrder(
      orderID: 'covered-confirmed-order',
      clientOrderID: original.clientOrderID,
      biz: 'withdraw',
      currency: original.amount.currency,
      amount: original.amount.decimal,
      status: 'withdraw_pending',
      toAddress: original.toAddress,
      fee: '0.25',
    ));
    await tester.pumpAndSettle();
    expect(find.text('新的页面'), findsOneWidget);
    expect(find.text('提现申请已提交，等待审核'), findsNothing);
    expect(operation.draft, isNull);
    expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
    expect(api.writes, isEmpty);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.byType(WithdrawChainReviewScreen), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });

  for (final policyFails in [false, true]) {
    testWidgets(
        'submitted draft restores and queries despite ${policyFails ? 'failed' : 'missing'} new policy',
        (tester) async {
      final api = _PolicyApi()..rule = null;
      if (policyFails) {
        api.onRules =
            () => Future.error(StateError('fixture policy unavailable'));
      }
      final operation = testWalletOperation(WalletOperationKind.withdraw, api,
          accountID: 'restored-withdraw-user');
      final original = WalletOperationDraft(
        kind: WalletOperationKind.withdraw,
        clientOrderID: 'frozen-original-client-order',
        amount: FundAmount.parse('1.25', FundCurrency.usdt),
        toAddress: walletOperationTestAddress,
        submitted: true,
        orderID: 'original-server-order',
      );
      await operation.store.save(original);
      api.lastOrder = WalletFundOrder(
        orderID: original.orderID,
        clientOrderID: original.clientOrderID,
        biz: 'withdraw',
        currency: FundCurrency.usdt,
        amount: '1.25',
        status: 'withdraw_done',
        toAddress: walletOperationTestAddress,
        fee: '0.25',
      );
      await pumpWalletOperation(
          tester,
          WithdrawChainReviewScreen(
            coin: withdrawalTestCoin(FundCurrency.usdt),
            payMethod: withdrawalTestMethod(FundCurrency.usdt),
            toAddress: 'different-new-address',
            amountMinor: 50000000,
            coordinator: operation,
          ));
      expect(operation.draft!.clientOrderID, original.clientOrderID);
      expect(find.text('1.25 USDT'), findsOneWidget);
      expect(find.text('原交易状态待确认，请勿重复提交'), findsNothing);
      final query = find.byKey(const ValueKey('wallet-operation-query'));
      await tester.ensureVisible(query);
      await tester.tap(query);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(api.queriedIDs, [original.orderID]);
      expect(api.writes, isEmpty);
      expect(operation.draft, isNull);
      expect(operation.receipt, isNull);
      expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
      expect(
          find.byKey(const ValueKey('wallet-operation-query')), findsNothing);
      expect(find.textContaining('业务单号：'), findsNothing);
    });
  }

  for (final locale in const [
    Locale('zh', 'CN'),
    Locale('zh', 'TW'),
    Locale('en'),
    Locale('ja'),
    Locale('ko'),
  ]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'rule summary wraps at 320px and 2x text in $locale ${brightness.name}',
          (tester) async {
        final api = _PolicyApi();
        await pumpWalletOperation(
            tester,
            Builder(
                builder: (context) => Localizations.override(
                    context: context, locale: locale, child: _page(api))),
            brightness: brightness,
            size: const Size(320, 640),
            textScale: 2);
        await tester.ensureVisible(
            find.byKey(const ValueKey('wallet-withdraw-total-debit')));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('wallet-withdraw-confirm')), 300,
            scrollable: find
                .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
