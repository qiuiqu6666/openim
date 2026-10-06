import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/order/wallet_order_events.dart';
import 'package:openim/services/fund_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wallet_operation_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'preparing withdrawal persists one immutable business ID without a write',
      () async {
    final api = WalletOperationTestApi();
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    final amount = FundAmount.parse('2.123456', FundCurrency.usdt);
    final prepared = await operation.prepareWithdrawal(
        amount: amount, toAddress: walletOperationTestAddress);
    final same = await operation.prepareWithdrawal(
        amount: amount, toAddress: walletOperationTestAddress);
    expect(same.clientOrderID, prepared.clientOrderID);
    expect(prepared.submitted, false);
    expect(api.writes, isEmpty);
    await expectLater(
        operation.submit(
            amount: FundAmount.parse('2.123455', FundCurrency.usdt),
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsStateError);
    expect(api.writes, isEmpty);
    await operation.submit(
        amount: amount,
        toAddress: walletOperationTestAddress,
        payPassword: '123456',
        verifyChallengeID: 'proof-1',
        verifyCode: '654321');
    expect(api.writes.single['clientOrderID'], prepared.clientOrderID);
    expect(api.writes.single['verifyChallengeID'], 'proof-1');
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(preferences.getKeys().single)!;
    expect(saved, isNot(contains('proof-1')));
    expect(saved, isNot(contains('654321')));
    expect(saved, isNot(contains('"123456"')));
  });

  test(
      'withdrawal timeout recovers by original client ID through manual review',
      () async {
    final api = WalletOperationTestApi()
      ..onWithdraw = (_) => Future.error(
          const FundApiException(-1, 'timeout', isUncertain: true));
    final first = testWalletOperation(WalletOperationKind.withdraw, api);
    final amount = FundAmount.parse('10', FundCurrency.usdt);
    await expectLater(
        first.submit(
            amount: amount,
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final original = first.draft!;
    first.dispose();
    final restored = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(restored.dispose);
    await restored.load();
    api.lastOrder = WalletFundOrder(
        orderID: 'manual-review',
        clientOrderID: original.clientOrderID,
        biz: 'withdraw',
        currency: amount.currency,
        amount: amount.decimal,
        status: 'withdraw_approved',
        toAddress: walletOperationTestAddress,
        fee: '1');
    final reviewed = await restored.refreshOrder();
    expect(reviewed.accepted, true);
    expect(reviewed.terminal, false);
    expect(reviewed.description, '审核已通过，等待出款');
    expect(restored.canStartNew, false);
    expect(api.queriedClientIDs, [original.clientOrderID]);
    expect(api.writes, hasLength(1));
    api.lastOrder = WalletFundOrder(
        orderID: 'manual-review',
        clientOrderID: original.clientOrderID,
        biz: 'withdraw',
        currency: amount.currency,
        amount: amount.decimal,
        status: 'withdraw_failed',
        toAddress: walletOperationTestAddress,
        fee: '1');
    final rejected = await restored.refreshOrder();
    expect(rejected.accepted, false);
    expect(rejected.terminal, true);
    expect(rejected.description, '提现已退回');
    expect(restored.canStartNew, true);
    expect(api.queriedIDs, ['manual-review']);
    expect(api.writes, hasLength(1));
  });

  test('local range rejection never leaves a submitted durable marker',
      () async {
    final api = WalletOperationTestApi();
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    await expectLater(
        operation.submit(
            amount: FundAmount.parse('9223372036854.775808', FundCurrency.usdt),
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsFormatException);
    expect(api.writes, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(operation.unresolved, isFalse);
  });

  test(
      'partial success preserves service order ID for GET recovery without rePOST',
      () async {
    final api = WalletOperationTestApi();
    api.onWithdraw = (_) => Future.error(const FundApiException(
        -1, 'missing fee',
        isUncertain: true, orderID: 'known-partial-order'));
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    await expectLater(
        operation.submit(
            amount: FundAmount.parse('6', FundCurrency.trx),
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    expect(operation.draft!.orderID, 'known-partial-order');
    api.lastOrder = const WalletFundOrder(
        orderID: 'known-partial-order',
        biz: 'withdraw',
        currency: FundCurrency.trx,
        amount: '6',
        status: 'withdraw_done',
        toAddress: walletOperationTestAddress,
        fee: '0.31');
    final result = await operation.refreshOrder();
    expect(result.fee, '0.31');
    expect(result.accepted, isTrue);
    expect(api.queriedIDs, ['known-partial-order']);
    expect(api.writes, hasLength(1));
  });

  test(
      'uncertain withdrawal persists original body without password and cannot resend after reopen',
      () async {
    final api = WalletOperationTestApi();
    api.onWithdraw = (_) =>
        Future.error(const FundApiException(-1, 'timeout', isUncertain: true));
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    await expectLater(
        operation.submit(
            amount: FundAmount.parse('1.123456', FundCurrency.trx),
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final original = operation.draft!;
    expect(operation.unresolved, isTrue);
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(preferences.getKeys().single)!;
    expect(saved, isNot(contains('payPassword')));
    expect(saved, isNot(contains('"password"')));
    operation.dispose();

    final restored = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.draft!.sameRequest(original), isTrue);
    await expectLater(
        restored.submit(
            amount: original.amount,
            toAddress: original.toAddress,
            payPassword: '654321'),
        throwsStateError);
    await expectLater(
        restored.refreshOrder(), throwsA(isA<FundApiException>()));
    await expectLater(restored.startNewOperation(), throwsStateError);
    expect(api.writes, hasLength(1));
    expect(api.queriedIDs, isEmpty);
    expect(api.queriedClientIDs, [original.clientOrderID]);

    final differentAccount = testWalletOperation(
        WalletOperationKind.withdraw, api,
        accountID: 'another-user');
    addTearDown(differentAccount.dispose);
    await differentAccount.load();
    expect(differentAccount.draft, isNull);
  });

  test('simultaneous pages share submission exclusion before network starts',
      () async {
    final api = WalletOperationTestApi();
    final response = Completer<WalletWithdrawResult>();
    api.onWithdraw = (_) => response.future;
    final first = testWalletOperation(WalletOperationKind.withdraw, api);
    final second = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final amount = FundAmount.parse('2', FundCurrency.usdt);
    final attempt = first.submit(
        amount: amount,
        toAddress: walletOperationTestAddress,
        payPassword: '123456');
    await expectLater(
        second.submit(
            amount: amount,
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsStateError);
    await Future<void>.delayed(Duration.zero);
    expect(api.writes, hasLength(1));
    response.complete(WalletWithdrawResult(
        order: WalletFundOrder(
            orderID: 'service-1',
            biz: 'withdraw',
            currency: FundCurrency.usdt,
            amount: '2',
            status: 'withdraw_done',
            toAddress: walletOperationTestAddress),
        fee: '0.37'));
    final result = await attempt;
    expect(result.description, '已登记出款');
    expect(result.description, isNot(contains('到账')));
  });

  test(
      'definite password refusal retries same ID and explicit new action generates another ID',
      () async {
    final api = WalletOperationTestApi();
    api.onWithdraw =
        (_) => Future.error(const FundApiException(20035, '支付密码错误'));
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    final amount = FundAmount.parse('3', FundCurrency.usdt);
    await expectLater(
        operation.submit(
            amount: amount,
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final id = operation.draft!.clientOrderID;
    expect(operation.unresolved, isFalse);
    api.onWithdraw = null;
    await operation.submit(
        amount: amount,
        toAddress: walletOperationTestAddress,
        payPassword: '654321');
    expect(api.writes.last['clientOrderID'], id);
    await operation.startNewOperation();
    await operation.submit(
        amount: amount,
        toAddress: walletOperationTestAddress,
        payPassword: '123456');
    expect(api.writes.last['clientOrderID'], isNot(id));
  });

  test(
      'known order recovery uses service ID GET and emits account-scoped invalidation',
      () async {
    final api = WalletOperationTestApi();
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    final signals = <String>[];
    final subscription = WalletOrderEvents.balanceChanges.listen(signals.add);
    addTearDown(subscription.cancel);
    await operation.submit(
        amount: FundAmount.parse('4', FundCurrency.trx),
        toAddress: walletOperationTestAddress,
        payPassword: '123456');
    final serviceID = operation.draft!.orderID;
    final restored = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(restored.dispose);
    await restored.load();
    await restored.refreshOrder();
    await Future<void>.delayed(Duration.zero);
    expect(api.queriedIDs, [serviceID]);
    expect(api.writes, hasLength(1));
    expect(signals, hasLength(2));
    expect(signals, everyElement('https://wallet.test:fixture-user'));
  });

  test(
      'account switch suppresses success while preserving original known order',
      () async {
    var current = true;
    final api = WalletOperationTestApi();
    final response = Completer<WalletWithdrawResult>();
    api.onWithdraw = (_) => response.future;
    final operation = testWalletOperation(WalletOperationKind.withdraw, api,
        isCurrent: () => current);
    addTearDown(operation.dispose);
    final pending = operation.submit(
        amount: FundAmount.parse('5', FundCurrency.usdt),
        toAddress: walletOperationTestAddress,
        payPassword: '123456');
    await Future<void>.delayed(Duration.zero);
    current = false;
    final expectation = expectLater(pending, throwsStateError);
    response.complete(WalletWithdrawResult(
        order: WalletFundOrder(
            orderID: 'old-account-order',
            biz: 'withdraw',
            currency: FundCurrency.usdt,
            amount: '5',
            status: 'withdraw_done',
            toAddress: walletOperationTestAddress),
        fee: '0.19'));
    await expectation;
    final restored = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.draft!.orderID, 'old-account-order');
  });

  test('quoted swap timeout persists its original quote and never a password',
      () async {
    final api = WalletOperationTestApi();
    final amount = FundAmount.parse('1.123456', FundCurrency.usdt);
    final quote =
        await api.fetchSwapQuote(amount: amount, toCurrency: FundCurrency.bi99);
    api.onSwap = (_) =>
        Future.error(const FundApiException(-1, 'timeout', isUncertain: true));
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    await expectLater(
        operation.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: quote,
            payPassword: '654321'),
        throwsA(isA<FundApiException>()));
    final original = operation.draft!;
    expect(original.quoteID, quote.quoteID);
    expect(original.expectedReceived, quote.estimatedReceived.decimal);
    expect(original.submitted, true);
    expect(original.orderID, isEmpty);
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(preferences.getKeys().single)!;
    final json = jsonDecode(saved) as Map<String, dynamic>;
    expect(json['quoteID'], quote.quoteID);
    expect(json['expectedReceived'], quote.estimatedReceived.decimal);
    expect(json['clientOrderID'], original.clientOrderID);
    expect(json.containsKey('payPassword'), false);
    expect(saved, isNot(contains('"654321"')));
    operation.dispose();

    final restored = testWalletOperation(WalletOperationKind.swap, api);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.draft!.sameRequest(original), true);
    expect(restored.draft!.quoteID, quote.quoteID);
    expect(restored.draft!.expectedReceived, quote.estimatedReceived.decimal);
    await expectLater(
        restored.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: quote,
            payPassword: '123456'),
        throwsStateError);
    await expectLater(restored.startNewOperation(), throwsStateError);
    expect(api.writes, hasLength(1));
    expect(api.writes.single['quoteID'], quote.quoteID);
    expect(api.queriedIDs, isEmpty);
    expect(api.queriedClientIDs, isEmpty);
  });

  test('wrong swap password retries the same business ID and quoted amount',
      () async {
    final api = WalletOperationTestApi();
    final amount = FundAmount.parse('1.25', FundCurrency.usdt);
    final quote =
        await api.fetchSwapQuote(amount: amount, toCurrency: FundCurrency.bi99);
    api.onSwap = (_) => Future.error(const FundApiException(20035, '支付密码错误'));
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    addTearDown(operation.dispose);
    await expectLater(
        operation.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: quote,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final original = operation.draft!;
    expect(operation.unresolved, false);
    expect(original.submitted, false);
    api.onSwap = null;
    final result = await operation.submit(
        amount: amount,
        toCurrency: FundCurrency.bi99,
        quote: quote,
        payPassword: '654321');
    expect(api.writes, hasLength(2));
    expect(api.writes.map((write) => write['clientOrderID']),
        everyElement(original.clientOrderID));
    expect(api.writes.map((write) => write['quoteID']),
        everyElement(quote.quoteID));
    expect(result.received, quote.estimatedReceived.decimal);
    expect(result.terminal, true);
    expect(operation.draft!.terminal, true);
  });

  test('a frozen swap cannot reuse its business ID with a different quote',
      () async {
    final api = WalletOperationTestApi();
    final amount = FundAmount.parse('1.25', FundCurrency.usdt);
    final quote =
        await api.fetchSwapQuote(amount: amount, toCurrency: FundCurrency.bi99);
    api.onSwap = (_) => Future.error(const FundApiException(20035, '支付密码错误'));
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    addTearDown(operation.dispose);
    await expectLater(
        operation.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: quote,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final original = operation.draft!;
    final replacement =
        await api.fetchSwapQuote(amount: amount, toCurrency: FundCurrency.bi99);
    expect(replacement.quoteID, isNot(quote.quoteID));
    await expectLater(
        operation.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: replacement,
            payPassword: '654321'),
        throwsStateError);
    expect(operation.draft!.sameRequest(original), true);
    expect(operation.draft!.clientOrderID, original.clientOrderID);
    expect(operation.draft!.quoteID, quote.quoteID);
    expect(api.writes, hasLength(1));
  });

  test('by-client swap recovery rejects a changed quote or received amount',
      () async {
    final api = WalletOperationTestApi();
    final amount = FundAmount.parse('1.25', FundCurrency.usdt);
    final quote =
        await api.fetchSwapQuote(amount: amount, toCurrency: FundCurrency.bi99);
    api.onSwap = (_) =>
        Future.error(const FundApiException(-1, 'timeout', isUncertain: true));
    final first = testWalletOperation(WalletOperationKind.swap, api);
    await expectLater(
        first.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: quote,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final original = first.draft!;
    first.dispose();
    final restored = testWalletOperation(WalletOperationKind.swap, api);
    addTearDown(restored.dispose);
    await restored.load();

    WalletFundOrder recovered({String? quoteID, String? received}) =>
        WalletFundOrder(
            orderID: 'recovered-swap',
            clientOrderID: original.clientOrderID,
            biz: 'swap',
            currency: amount.currency,
            amount: amount.decimal,
            status: 'done',
            targetCurrency: FundCurrency.bi99,
            targetAmount: received ?? quote.estimatedReceived.decimal,
            quoteID: quoteID ?? quote.quoteID);

    for (final wrong in [
      recovered(quoteID: 'another-quote'),
      recovered(received: '10.01'),
    ]) {
      api.onOrderByClient = (_) async => wrong;
      await expectLater(restored.refreshOrder(), throwsFormatException);
      expect(restored.receipt, null);
      expect(restored.unresolved, true);
      expect(restored.draft!.sameRequest(original), true);
      expect(restored.draft!.orderID, isEmpty);
      expect(restored.canStartNew, false);
    }
    api.onOrderByClient = (_) async => recovered();
    final result = await restored.refreshOrder();
    expect(result.accepted, true);
    expect(result.terminal, true);
    expect(result.received, quote.estimatedReceived.decimal);
    expect(restored.draft!.orderID, 'recovered-swap');
    expect(restored.draft!.quoteID, quote.quoteID);
    expect(restored.draft!.terminal, true);
    expect(restored.unresolved, false);
    expect(api.queriedClientIDs, everyElement(original.clientOrderID));
    expect(api.queriedClientIDs, hasLength(3));
    expect(api.queriedIDs, isEmpty);
    expect(api.writes, hasLength(1));
  });

  test('legacy swap drafts recover by client ID without adding a new quote',
      () async {
    final api = WalletOperationTestApi();
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    addTearDown(operation.dispose);
    final legacy = WalletOperationDraft(
        kind: WalletOperationKind.swap,
        clientOrderID: 'legacy-swap-client',
        amount: FundAmount.parse('2', FundCurrency.trx),
        toCurrency: FundCurrency.usdt,
        submitted: true);
    await operation.store.save(legacy);
    api.lastOrder = const WalletFundOrder(
        orderID: 'legacy-swap-order',
        clientOrderID: 'legacy-swap-client',
        biz: 'swap',
        currency: FundCurrency.trx,
        amount: '2',
        status: 'done',
        targetCurrency: FundCurrency.usdt,
        targetAmount: '0.5');
    await operation.load();
    final result = await operation.refreshOrder();
    expect(result.received, '0.5');
    expect(result.terminal, true);
    expect(operation.draft!.quoteID, null);
    expect(operation.draft!.expectedReceived, null);
    expect(operation.draft!.clientOrderID, legacy.clientOrderID);
    expect(api.queriedClientIDs, [legacy.clientOrderID]);
    expect(api.quoteRequests, isEmpty);
    expect(api.writes, isEmpty);
  });

  test('pending quote fields are paired while old drafts remain readable', () {
    final legacy = WalletOperationDraft(
        kind: WalletOperationKind.swap,
        clientOrderID: 'legacy-swap-client',
        amount: FundAmount.parse('2', FundCurrency.trx),
        toCurrency: FundCurrency.usdt,
        submitted: true);
    final json = legacy.toJson();
    final decoded = WalletOperationDraft.fromJson(json);
    expect(decoded.quoteID, null);
    expect(decoded.expectedReceived, null);
    expect(decoded.sameRequest(legacy), true);
    for (final incomplete in [
      {...json, 'quoteID': 'quote-1'},
      {...json, 'expectedReceived': '0.5'},
    ]) {
      expect(() => WalletOperationDraft.fromJson(incomplete),
          throwsFormatException);
    }
    final quoted = WalletOperationDraft.fromJson(
        {...json, 'quoteID': 'quote-1', 'expectedReceived': '0.5'});
    expect(quoted.quoteID, 'quote-1');
    expect(quoted.expectedReceived, '0.5');
  });

  test('a missing by-client order never clears or resubmits the original swap',
      () async {
    final api = WalletOperationTestApi();
    final amount = FundAmount.parse('1.25', FundCurrency.usdt);
    final quote =
        await api.fetchSwapQuote(amount: amount, toCurrency: FundCurrency.bi99);
    api.onSwap = (_) =>
        Future.error(const FundApiException(-1, 'timeout', isUncertain: true));
    api.onOrderByClient =
        (_) => Future.error(const FundApiException(20032, '订单不存在'));
    final operation = testWalletOperation(WalletOperationKind.swap, api);
    addTearDown(operation.dispose);
    await expectLater(
        operation.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: quote,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final original = operation.draft!;
    final preferences = await SharedPreferences.getInstance();
    final key = preferences.getKeys().single;
    final saved = preferences.getString(key);
    await expectLater(
        operation.refreshOrder(),
        throwsA(isA<FundApiException>()
            .having((error) => error.code, 'not found', 20032)));
    expect(operation.draft!.sameRequest(original), true);
    expect(preferences.getString(key), saved);
    expect(operation.unresolved, true);
    expect(operation.canStartNew, false);
    expect(operation.receipt, null);
    await expectLater(operation.startNewOperation(), throwsStateError);
    await expectLater(
        operation.submit(
            amount: amount,
            toCurrency: FundCurrency.bi99,
            quote: quote,
            payPassword: '654321'),
        throwsStateError);
    expect(api.writes, hasLength(1));
    expect(api.queriedClientIDs, [original.clientOrderID]);
    expect(api.quoteRequests, hasLength(1));
  });

  for (final from in FundCurrency.values) {
    for (final to
        in FundCurrency.values.where((currency) => currency != from)) {
      test('exact ${from.code} -> ${to.code} swap without local quotation',
          () async {
        final api = WalletOperationTestApi();
        final operation = testWalletOperation(WalletOperationKind.swap, api);
        addTearDown(operation.dispose);
        final amount = FundAmount.parse(
            from == FundCurrency.bi99 ? '1.23' : '1.234567', from);
        final result = await operation.submit(
            amount: amount, toCurrency: to, payPassword: '123456');
        expect(api.writes.single['currency'], from.code);
        expect(api.writes.single['toCurrency'], to.code);
        expect(api.writes.single['amount'], amount.decimal);
        final received = to == FundCurrency.bi99 ? '2.34' : '2.345678';
        expect(result.received, received);
        expect(result.description, contains(received));
      });
    }
  }
}
