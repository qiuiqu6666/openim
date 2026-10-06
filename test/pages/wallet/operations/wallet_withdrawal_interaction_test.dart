import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_coordinator.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/services/fund_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wallet_operation_test_support.dart';

class _FailedConfirmedClear extends WalletOperationPendingStore {
  _FailedConfirmedClear() : super(accountKey: 'confirmed-clear-failure');
  @override
  Future<void> clearConfirmedWithdrawal(WalletOperationDraft draft) async =>
      throw StateError('Storage clear failed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'closing an unsubmitted authorization releases the frozen business draft',
      () async {
    final api = WalletOperationTestApi();
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    final amount = FundAmount.parse('2', FundCurrency.usdt);
    final original = await operation.prepareWithdrawal(
        amount: amount, toAddress: walletOperationTestAddress);
    expect(await operation.finishWithdrawalInteraction(), isTrue);
    expect(operation.draft, isNull);
    expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
    final next = await operation.prepareWithdrawal(
        amount: FundAmount.parse('3', FundCurrency.usdt),
        toAddress: walletOperationTestAddress);
    expect(next.clientOrderID, isNot(original.clientOrderID));
    expect(api.writes, isEmpty);
  });

  test(
      'closing a definite SMS refusal allows a later edited request with a new ID',
      () async {
    final api = WalletOperationTestApi()
      ..onWithdraw =
          (_) => Future.error(const FundApiException(20078, 'Proof rejected'));
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    await expectLater(
        operation.submit(
            amount: FundAmount.parse('2', FundCurrency.usdt),
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final originalID = operation.draft!.clientOrderID;
    expect(operation.draft!.submitted, isFalse);
    expect(await operation.finishWithdrawalInteraction(), isTrue);
    expect(operation.draft, isNull);
    final next = await operation.prepareWithdrawal(
        amount: FundAmount.parse('3', FundCurrency.usdt),
        toAddress: walletOperationTestAddress);
    expect(next.clientOrderID, isNot(originalID));
    expect(api.writes, hasLength(1));
  });

  test(
      'an API-confirmed pending review ends this interaction without waiting for payout',
      () async {
    final api = WalletOperationTestApi();
    api.onWithdraw = (request) async => WalletWithdrawResult(
        order: WalletFundOrder(
            orderID: 'pending-review',
            clientOrderID: request['clientOrderID'] as String,
            biz: 'withdraw',
            currency: FundCurrency.usdt,
            amount: request['amount'] as String,
            status: 'withdraw_pending',
            toAddress: walletOperationTestAddress,
            fee: '0.25'),
        fee: '0.25');
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    final receipt = await operation.submit(
        amount: FundAmount.parse('2', FundCurrency.usdt),
        toAddress: walletOperationTestAddress,
        payPassword: '123456');
    final originalID = operation.draft!.clientOrderID;
    expect(receipt.accepted, isTrue);
    expect(receipt.terminal, isFalse);
    expect(await operation.finishWithdrawalInteraction(), isTrue);
    expect(operation.draft, isNull);
    expect(operation.receipt, isNull);
    expect(await operation.store.read(WalletOperationKind.withdraw), isNull);
    final next = await operation.prepareWithdrawal(
        amount: FundAmount.parse('3', FundCurrency.usdt),
        toAddress: walletOperationTestAddress);
    expect(next.clientOrderID, isNot(originalID));
    expect(api.writes, hasLength(1));
  });

  test('unknown results retain the ID until an authenticated query confirms it',
      () async {
    final api = WalletOperationTestApi()
      ..onWithdraw = (_) => Future.error(
          const FundApiException(-1, 'timeout', isUncertain: true));
    final operation = testWalletOperation(WalletOperationKind.withdraw, api);
    addTearDown(operation.dispose);
    final amount = FundAmount.parse('2', FundCurrency.usdt);
    await expectLater(
        operation.submit(
            amount: amount,
            toAddress: walletOperationTestAddress,
            payPassword: '123456'),
        throwsA(isA<FundApiException>()));
    final original = operation.draft!;
    expect(await operation.finishWithdrawalInteraction(), isFalse);
    expect(operation.draft!.sameRequest(original), isTrue);
    expect(
        (await operation.store.read(WalletOperationKind.withdraw))!
            .sameRequest(original),
        isTrue);
    await expectLater(
        operation.prepareWithdrawal(
            amount: amount, toAddress: walletOperationTestAddress),
        throwsStateError);
    api.lastOrder = WalletFundOrder(
        orderID: 'queried-pending',
        clientOrderID: original.clientOrderID,
        biz: 'withdraw',
        currency: amount.currency,
        amount: amount.decimal,
        status: 'withdraw_pending',
        toAddress: walletOperationTestAddress,
        fee: '0.25');
    await operation.refreshOrder();
    expect(await operation.finishWithdrawalInteraction(), isTrue);
    expect(operation.draft, isNull);
    expect(api.queriedClientIDs, [original.clientOrderID]);
    expect(api.writes, hasLength(1));
  });

  test('failed durable cleanup leaves the confirmed interaction locked',
      () async {
    final api = WalletOperationTestApi();
    final operation = WalletOperationCoordinator(
        kind: WalletOperationKind.withdraw,
        api: api,
        store: _FailedConfirmedClear(),
        accountID: 'fixture-user',
        serverURL: 'https://wallet.test',
        isAccountCurrent: () => true);
    addTearDown(operation.dispose);
    await operation.submit(
        amount: FundAmount.parse('2', FundCurrency.usdt),
        toAddress: walletOperationTestAddress,
        payPassword: '123456');
    final original = operation.draft!;
    await expectLater(
        operation.finishWithdrawalInteraction(), throwsStateError);
    expect(operation.draft!.sameRequest(original), isTrue);
    expect(operation.receipt, isNotNull);
    expect(operation.canSubmit, isFalse);
    expect((await operation.store.read(WalletOperationKind.withdraw))!.orderID,
        original.orderID);
    expect(api.writes, hasLength(1));
  });

  test(
      'confirmed cleanup rejects a changed request or conflicting durable order marker',
      () async {
    final store = WalletOperationPendingStore(accountKey: 'marker-test');
    final confirmed = WalletOperationDraft(
        kind: WalletOperationKind.withdraw,
        clientOrderID: 'same-client',
        amount: FundAmount.parse('2', FundCurrency.usdt),
        toAddress: walletOperationTestAddress,
        submitted: true,
        orderID: 'confirmed-order');
    await store.save(confirmed);
    for (final altered in [
      confirmed.withState(orderID: 'another-order'),
      confirmed.withState(submitted: false),
      WalletOperationDraft(
          kind: WalletOperationKind.withdraw,
          clientOrderID: 'another-client',
          amount: confirmed.amount,
          toAddress: confirmed.toAddress,
          submitted: true,
          orderID: confirmed.orderID),
      WalletOperationDraft(
          kind: WalletOperationKind.withdraw,
          clientOrderID: confirmed.clientOrderID,
          amount: FundAmount.parse('3', FundCurrency.usdt),
          toAddress: confirmed.toAddress,
          submitted: true,
          orderID: confirmed.orderID),
    ]) {
      await expectLater(
          store.clearConfirmedWithdrawal(altered), throwsStateError);
      expect((await store.read(WalletOperationKind.withdraw))!.orderID,
          confirmed.orderID);
    }
    await store.save(confirmed.withState(submitted: false, orderID: ''));
    await expectLater(
        store.clearConfirmedWithdrawal(confirmed), throwsStateError);
    expect(await store.read(WalletOperationKind.withdraw), isNotNull);
  });
}
