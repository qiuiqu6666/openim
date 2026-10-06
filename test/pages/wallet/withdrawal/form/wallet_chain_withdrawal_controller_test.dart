import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/currency_rules/wallet_withdrawal_policy.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_coordinator.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/withdrawal/form/wallet_chain_withdrawal_controller.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/wallet_fund_test_api.dart';

class _MemoryStore extends WalletOperationPendingStore {
  _MemoryStore() : super(accountKey: 'test-account');
  WalletOperationDraft? value;
  bool failClear = false;
  int confirmedClearCalls = 0;
  Completer<void>? confirmedClearGate;
  @override
  Future<WalletOperationDraft?> read(WalletOperationKind kind) async => value;
  @override
  Future<void> save(WalletOperationDraft draft) async => value = draft;
  @override
  Future<void> clearForNewAction(WalletOperationDraft draft) async {
    if (failClear) throw StateError('Clear failed');
    value = null;
  }

  @override
  Future<void> clearConfirmedWithdrawal(WalletOperationDraft draft) async {
    confirmedClearCalls++;
    if (confirmedClearGate != null) await confirmedClearGate!.future;
    if (failClear) throw StateError('Clear failed');
    value = null;
  }
}

class _Api extends WalletTestFundApi {
  int writes = 0;
  @override
  Future<WalletWithdrawResult> withdraw({
    required String clientOrderID,
    required FundAmount amount,
    required String toAddress,
    required String payPassword,
    String? verifyChallengeID,
    String? verifyCode,
  }) async {
    writes++;
    throw StateError('Controller tests must never submit a withdrawal');
  }
}

class _Operation extends WalletOperationCoordinator {
  _Operation(WalletFundApi api, WalletOperationPendingStore store,
      bool Function() current)
      : super(
            kind: WalletOperationKind.withdraw,
            api: api,
            store: store,
            accountID: 'self',
            serverURL: 'https://chat.test',
            isAccountCurrent: current);
  void showDraft(WalletOperationDraft value) {
    draft = value;
    notifyListeners();
  }
}

class _Fixture {
  _Fixture(
      {FundCurrency initialCurrency = FundCurrency.usdt,
      WalletOperationDraft? draft}) {
    store.value = draft;
    operation = _Operation(api, store, () => owner == 'owner-a');
    controller = WalletChainWithdrawalController(
      initialCurrency: initialCurrency,
      api: api,
      operation: operation,
      accountProvider: () => owner,
    );
  }
  final api = _Api();
  final store = _MemoryStore();
  String owner = 'owner-a';
  late final _Operation operation;
  late final WalletChainWithdrawalController controller;
  bool _closed = false;
  Future<void> load() async {
    controller.setActive(true);
    await controller.load();
  }

  void enterValid() {
    controller.setAddress(testUsdtContract);
    controller.setAmount('1.123456');
    controller.selectNetwork();
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    controller.dispose();
    operation.dispose();
  }
}

WalletDepositAddress _rules({String minimum = '0.1', String fee = '0.25'}) =>
    WalletDepositAddress(
      status: 'ready',
      network: 'TRON',
      address: testDepositAddress,
      currencies: const [FundCurrency.usdt, FundCurrency.trx],
      confirmations: 19,
      usdtContract: testUsdtContract,
      currencyRules: {
        for (final currency in [FundCurrency.usdt, FundCurrency.trx])
          currency: WalletCurrencyRule(
            currency: currency,
            minWithdrawAmount: minimum,
            withdrawFee: fee,
            withdrawFeeCurrency: currency,
          ),
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'finishing a cancelled authorization preserves amount, address and network',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    await f.operation.prepareWithdrawal(
        amount: f.controller.amount!, toAddress: f.controller.address);
    expect(f.controller.canEdit, isFalse);
    await f.controller.finishInteraction();
    expect(f.operation.draft, isNull);
    expect(f.store.value, isNull);
    expect(f.controller.canEdit, isTrue);
    expect(f.controller.address, testUsdtContract);
    expect(f.controller.amountText, '1.123456');
    expect(f.controller.networkSelected, isTrue);
    expect(f.controller.canSubmit, isTrue);
    expect(f.api.writes, 0);
  });

  test('finishing an accepted pending receipt clears the address and amount',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    final amount = f.controller.amount!;
    final confirmed = WalletOperationDraft(
        kind: WalletOperationKind.withdraw,
        clientOrderID: 'accepted-client',
        amount: amount,
        toAddress: testUsdtContract,
        submitted: true,
        orderID: 'pending-order');
    f.store.value = confirmed;
    f.operation.receipt = WalletOperationReceipt(
        order: WalletFundOrder(
            orderID: confirmed.orderID,
            clientOrderID: confirmed.clientOrderID,
            biz: 'withdraw',
            currency: amount.currency,
            amount: amount.decimal,
            status: 'withdraw_pending',
            toAddress: testUsdtContract,
            fee: '0.25'));
    f.operation.showDraft(confirmed);
    await f.controller.finishInteraction();
    expect(f.operation.draft, isNull);
    expect(f.operation.receipt, isNull);
    expect(f.store.value, isNull);
    expect(f.controller.canEdit, isTrue);
    expect(f.controller.address, isEmpty);
    expect(f.controller.amountText, isEmpty);
    expect(f.controller.networkSelected, isTrue);
    expect(f.controller.canSubmit, isFalse);
    f.controller.setAddress(testUsdtContract);
    f.controller.setAmount('2');
    expect(f.controller.canSubmit, isTrue);
    expect(f.api.writes, 0);
  });

  test('finishing an unknown request preserves its frozen input and durable ID',
      () async {
    final draft = WalletOperationDraft(
        kind: WalletOperationKind.withdraw,
        clientOrderID: 'unknown-client',
        amount: FundAmount.parse('2', FundCurrency.usdt),
        toAddress: testUsdtContract,
        submitted: true);
    final f = _Fixture(draft: draft);
    addTearDown(f.dispose);
    await f.load();
    await f.controller.finishInteraction();
    expect(f.operation.draft!.clientOrderID, draft.clientOrderID);
    expect(f.store.value!.clientOrderID, draft.clientOrderID);
    expect(f.controller.canEdit, isFalse);
    expect(f.controller.amountText, '2');
    expect(f.controller.address, testUsdtContract);
    f.controller.setAmount('99');
    expect(f.controller.amountText, '2');
    expect(f.api.writes, 0);
  });

  test('concurrent finishes join one cleanup and preserve address and network',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    final amount = f.controller.amount!;
    final confirmed = WalletOperationDraft(
        kind: WalletOperationKind.withdraw,
        clientOrderID: 'joined-client',
        amount: amount,
        toAddress: testUsdtContract,
        submitted: true,
        orderID: 'joined-pending-order');
    f.store.value = confirmed;
    f.operation.receipt = WalletOperationReceipt(
        order: WalletFundOrder(
            orderID: confirmed.orderID,
            clientOrderID: confirmed.clientOrderID,
            biz: 'withdraw',
            currency: amount.currency,
            amount: amount.decimal,
            status: 'withdraw_pending',
            toAddress: testUsdtContract,
            fee: '0.25'));
    f.operation.showDraft(confirmed);
    f.store.confirmedClearGate = Completer<void>();
    final first = f.controller.finishInteraction();
    final second = f.controller.finishInteraction();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(f.store.confirmedClearCalls, 1);
    final joinedWhileClearing = f.controller.finishInteraction();
    expect(identical(first, joinedWhileClearing), isTrue);
    expect(f.controller.address, testUsdtContract);
    expect(f.controller.networkSelected, isTrue);
    f.store.confirmedClearGate!.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(await joinedWhileClearing, isTrue);
    expect(f.store.confirmedClearCalls, 1);
    expect(f.operation.draft, isNull);
    expect(f.store.value, isNull);
    expect(f.controller.address, isEmpty);
    expect(f.controller.networkSelected, isTrue);
    expect(f.controller.amountText, isEmpty);
    f.controller.setAddress(testUsdtContract);
    f.controller.setAmount('2');
    expect(f.controller.canSubmit, isTrue);
    expect(f.api.writes, 0);
  });

  test('reads only while active and resumes with one fresh read', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.controller.load();
    expect(f.api.addressCalls, 0);
    await f.load();
    expect(f.api.addressCalls, 1);
    expect(f.api.balanceCalls, 1);
    expect(f.controller.network, 'TRON');
    expect(f.controller.rule!.withdrawFee, '0.25');
    expect(f.controller.balance!.available.decimal, '12.345678');
    f.controller.setActive(false);
    await f.controller.load();
    expect(f.api.addressCalls, 1);
    await f.load();
    expect(f.api.addressCalls, 2);
    expect(f.api.writes, 0);
  });

  test('inactive late reads are discarded; queued resume never overlaps',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final pending = Completer<WalletDepositAddress>();
    f.api.respondAddress = () => pending.future;
    f.controller.setActive(true);
    final first = f.controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(f.api.addressCalls, 1);
    f.controller.setActive(false);
    pending.complete(depositAddressFixture());
    await first;
    expect(f.controller.rule, isNull);
    expect(f.controller.balance, isNull);
    f.api.respondAddress = null;
    await f.load();
    expect(f.api.addressCalls, 2);
    expect(f.controller.rule, isNotNull);
  });

  test('repeated coverage while pending queues only one resumed refresh',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final pending = Completer<WalletDepositAddress>();
    f.api.respondAddress = () => pending.future;
    f.controller.setActive(true);
    final first = f.controller.load();
    await Future<void>.delayed(Duration.zero);
    f.controller.setActive(false);
    f.controller.setActive(true);
    f.controller.setActive(false);
    f.controller.setActive(true);
    expect(f.api.addressCalls, 1);
    f.api.respondAddress = null;
    pending.complete(depositAddressFixture());
    await first;
    await f.controller.load();
    expect(f.api.addressCalls, 2);
    expect(f.api.balanceCalls, 2);
  });

  test('late data from a previous account never repopulates the form',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    final pending = Completer<WalletDepositAddress>();
    f.api.respondAddress = () => pending.future;
    f.controller.setActive(true);
    final first = f.controller.load();
    await Future<void>.delayed(Duration.zero);
    f.owner = 'owner-b';
    pending.complete(depositAddressFixture());
    await first;
    expect(f.controller.isCurrentAccount, isFalse);
    expect(f.controller.rule, isNull);
    expect(f.controller.balance, isNull);
    expect(f.controller.network, isNull);
    expect(f.controller.canSubmit, isFalse);
  });

  test(
      'strict checksum, self address and explicit network selection gate payment',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.controller.setAmount('1');
    f.controller.setAddress(testUsdtContract);
    expect(f.controller.addressValid, isTrue);
    expect(f.controller.networkSelected, isFalse);
    expect(f.controller.canSubmit, isFalse);
    f.controller.selectNetwork();
    expect(f.controller.canSubmit, isTrue);
    f.controller.setAddress(testDepositAddress);
    expect(f.controller.isSelfAddress, isTrue);
    expect(f.controller.canSubmit, isFalse);
    f.controller.setAddress('${testUsdtContract.substring(0, 33)}1');
    expect(f.controller.addressValid, isFalse);
    f.controller.setAddress('example.tron');
    expect(f.controller.addressValid, isFalse);
    expect(await f.controller.prepareSubmission(), isNull);
    expect(f.api.writes, 0);
  });

  test('all uses exact available less fee without consuming frozen funds',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    f.controller.applyAll();
    expect(f.controller.amountText, '12.095678');
    final snapshot = (await f.controller.prepareSubmission())!;
    expect(snapshot.amount.decimal, '12.095678');
    expect(snapshot.totalDebit.decimal, '12.345678');
    expect(snapshot.balance.frozen.decimal, '4.1');
    expect(snapshot.address, testUsdtContract);
    expect(snapshot.network, 'TRON');
    expect(f.controller.matches(snapshot), isTrue);
    expect(f.api.writes, 0);
  });

  test(
      'missing rules are unknown and failed reads can recover by explicit retry',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    f.api.address = depositAddressFixture(withRules: false);
    await f.load();
    f.enterValid();
    expect(f.controller.failed, isTrue);
    expect(f.controller.policyIssue, WalletWithdrawalPolicyIssue.incomplete);
    expect(f.controller.canSubmit, isFalse);
    f.api.respondBalances = () => Future.error(Exception('offline'));
    await f.controller.load();
    expect(f.controller.balance, isNull);
    expect(f.controller.failed, isTrue);
    f.api.respondBalances = null;
    f.api.address = depositAddressFixture();
    await f.controller.load();
    expect(f.controller.failed, isFalse);
    expect(f.controller.canSubmit, isTrue);
  });

  test(
      'fresh minimum and fee block a previously valid amount before authorization',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    expect(f.controller.canSubmit, isTrue);
    f.api.address = _rules(minimum: '2', fee: '0.5');
    expect(await f.controller.prepareSubmission(), isNull);
    expect(f.controller.rule!.withdrawFee, '0.5');
    expect(f.controller.policyIssue, WalletWithdrawalPolicyIssue.belowMinimum);
    expect(f.controller.canSubmit, isFalse);
    expect(f.api.writes, 0);
  });

  test('fresh balance must cover principal plus fee', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    f.api.balances = balancesFixture(usdt: '1.2');
    expect(await f.controller.prepareSubmission(), isNull);
    expect(f.controller.policyIssue,
        WalletWithdrawalPolicyIssue.insufficientBalance);
    expect(f.api.writes, 0);
  });

  test(
      'invalid precision and overflow remain invalid without silent truncation',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    f.controller.setAmount('1.1234567');
    expect(f.controller.amountText, '1.1234567');
    expect(f.controller.amount, isNull);
    f.controller.setAmount('1e2');
    expect(f.controller.amount, isNull);
    f.controller.setAmount('9223372036854.775808');
    expect(f.controller.amount!.units, BigInt.parse('9223372036854775808'));
    expect(f.controller.canSubmit, isFalse);
    expect(await f.controller.prepareSubmission(), isNull);
    expect(f.api.writes, 0);
    f.api.balances = balancesFixture(usdt: '9223372036855.1');
    f.controller.setAmount('9223372036854.775807');
    await f.controller.load();
    expect(f.controller.policyIssue, isNull);
    expect(f.controller.canSubmit, isFalse,
        reason: 'Principal plus fee exceeds int64');
    f.api.address = _rules(fee: '0');
    await f.controller.load();
    expect(f.controller.canSubmit, isTrue);
  });

  for (final submitted in [false, true]) {
    test(
        'restored cross-currency draft freezes parameters; submitted=$submitted',
        () async {
      final draft = WalletOperationDraft(
        kind: WalletOperationKind.withdraw,
        clientOrderID: 'persisted-id',
        amount: FundAmount.parse('2.000001', FundCurrency.trx),
        toAddress: testUsdtContract,
        submitted: submitted,
      );
      final f = _Fixture(draft: draft);
      addTearDown(f.dispose);
      await f.load();
      expect(f.controller.currency, FundCurrency.trx);
      expect(f.controller.address, testUsdtContract);
      expect(f.controller.amountText, '2.000001');
      expect(f.controller.canEdit, isFalse);
      expect(f.controller.networkSelected, isTrue);
      f.controller.setAddress(testDepositAddress);
      f.controller.setAmount('99');
      expect(f.controller.address, testUsdtContract);
      expect(f.controller.amountText, '2.000001');
      expect(f.controller.canSubmit, !submitted);
      final snapshot = await f.controller.prepareSubmission();
      expect(snapshot == null, submitted);
      expect(f.api.writes, 0);
      if (!submitted) {
        await f.operation.startNewOperation();
        await f.controller.load();
        expect(f.controller.canEdit, isTrue);
        expect(f.controller.address, isEmpty);
        expect(f.controller.amountText, isEmpty);
        expect(f.controller.currency, FundCurrency.usdt);
      }
    });
  }

  test('changing input during fresh preparation drops the old snapshot',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    final pending = Completer<WalletDepositAddress>();
    f.api.respondAddress = () => pending.future;
    final preparing = f.controller.prepareSubmission();
    f.controller.setAmount('2');
    pending.complete(depositAddressFixture());
    expect(await preparing, isNull);
    expect(f.controller.amountText, '2');
    expect(f.api.writes, 0);
  });

  test('preparation joins resumed loading then independently rechecks rules',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    f.controller.setActive(false);
    final pending = Completer<WalletDepositAddress>();
    f.api.respondAddress = () => pending.future;
    f.controller.setActive(true);
    final preparing = f.controller.prepareSubmission();
    expect(await f.controller.prepareSubmission(), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(f.api.addressCalls, 2);
    f.api.respondAddress = null;
    f.api.address = _rules(minimum: '2');
    pending.complete(depositAddressFixture());
    expect(await preparing, isNull);
    expect(f.api.addressCalls, 3);
    expect(f.controller.policyIssue, WalletWithdrawalPolicyIssue.belowMinimum);
    expect(f.api.writes, 0);
  });

  test('input changes while joining a resumed read cancel preparation',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    f.controller.setActive(false);
    final pending = Completer<WalletDepositAddress>();
    f.api.respondAddress = () => pending.future;
    f.controller.setActive(true);
    final preparing = f.controller.prepareSubmission();
    f.controller.setAmount('2');
    pending.complete(depositAddressFixture());
    expect(await preparing, isNull);
    expect(f.api.addressCalls, 2);
    expect(f.controller.amountText, '2');
  });

  test('late preparation refuses a switched account', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    final pending = Completer<WalletDepositAddress>();
    f.api.respondAddress = () => pending.future;
    final preparing = f.controller.prepareSubmission();
    f.owner = 'owner-b';
    pending.complete(depositAddressFixture());
    expect(await preparing, isNull);
    expect(f.controller.balance, isNull);
    expect(f.controller.canEdit, isFalse);
    expect(f.api.writes, 0);
  });

  test(
      'freezing an equivalent decimal preserves authorization for a refused draft',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    f.controller.setAmount('1.000000');
    final snapshot = (await f.controller.prepareSubmission())!;
    f.controller.setActive(false);
    f.operation.showDraft(WalletOperationDraft(
      kind: WalletOperationKind.withdraw,
      clientOrderID: 'refused-id',
      amount: snapshot.amount,
      toAddress: snapshot.address,
      submitted: false,
    ));
    expect(f.controller.amountText, '1');
    expect(f.controller.canEdit, isFalse);
    expect(f.controller.matches(snapshot), isTrue);
    expect(f.api.writes, 0);
  });

  test(
      'payment snapshot survives owned coverage but rejects edited or disposed inputs',
      () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    await f.load();
    f.enterValid();
    final snapshot = (await f.controller.prepareSubmission())!;
    f.controller.setActive(false);
    expect(f.controller.canSubmit, isFalse);
    expect(f.controller.matches(snapshot), isTrue);
    f.controller.setAmount('2');
    expect(f.controller.matches(snapshot), isFalse);
    f.dispose();
    expect(f.controller.matches(snapshot), isFalse);
  });

  test('default session fence rejects a new token for the same account',
      () async {
    SharedPreferences.setMockInitialValues({});
    await DataSp.init();
    Future<void> certificate(String token) async {
      await DataSp.putLoginCertificate(LoginCertificate.fromJson({
        'userID': 'self',
        'chatToken': token,
        'imToken': 'im-token',
      }));
    }

    await certificate('first-token');
    final api = _Api();
    final operation = WalletOperationCoordinator(
      kind: WalletOperationKind.withdraw,
      api: api,
      store: _MemoryStore(),
      accountID: 'self',
      serverURL: 'https://chat.test',
      isAccountCurrent: () => DataSp.userID == 'self',
    );
    final controller = WalletChainWithdrawalController(
        initialCurrency: FundCurrency.usdt, api: api, operation: operation);
    addTearDown(() {
      controller.dispose();
      operation.dispose();
    });
    controller.setActive(true);
    await controller.load();
    controller.setAddress(testUsdtContract);
    controller.setAmount('1');
    controller.selectNetwork();
    final snapshot = (await controller.prepareSubmission())!;
    await certificate('second-token');
    expect(controller.isCurrentAccount, isFalse);
    expect(controller.matches(snapshot), isFalse);
    expect(controller.balance, isNull);
    expect(api.writes, 0);
  });
}
