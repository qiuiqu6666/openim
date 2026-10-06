import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/withdrawal/amount_entry/wallet_withdrawal_rules_controller.dart';

import '../../data/wallet_fund_test_api.dart';

void main() {
  test(
      'repeated coverage during a pending read does not duplicate the next refresh',
      () async {
    final pending = Completer<WalletDepositAddress>();
    final api = WalletTestFundApi()..respondAddress = () => pending.future;
    final controller = WalletWithdrawalRulesController(
        currency: FundCurrency.usdt, api: api, accountProvider: () => 'owner');
    addTearDown(controller.dispose);
    controller.setActive(true);
    final first = controller.load();
    controller.setActive(false);
    controller.setActive(true);
    controller.setActive(false);
    pending.complete(depositAddressFixture());
    await first;
    api.respondAddress = null;
    controller.setActive(true);
    await controller.load();
    await Future<void>.delayed(Duration.zero);
    expect(api.addressCalls, 2);
    expect(controller.rule!.isWithdrawalComplete, true);
  });
  test('pending allocation already supplies rules, resume reads fresh config',
      () async {
    final api = WalletTestFundApi(address: depositAddressFixture(ready: false));
    final controller = WalletWithdrawalRulesController(
        currency: FundCurrency.usdt, api: api, accountProvider: () => 'owner');
    addTearDown(controller.dispose);
    controller.setActive(true);
    await controller.load();
    expect(controller.rule!.withdrawFee, '0.25');
    expect(controller.failed, false);
    expect(api.addressCalls, 1);
    controller.setActive(false);
    api.address = _address('0.000001');
    controller.setActive(true);
    await controller.load();
    expect(controller.rule!.withdrawFee, '0.000001');
    expect(api.addressCalls, 2);
  });

  test('covered and changed-account late reads never restore the old rule',
      () async {
    final pending = Completer<WalletDepositAddress>();
    final api = WalletTestFundApi()..respondAddress = () => pending.future;
    var owner = 'a';
    final controller = WalletWithdrawalRulesController(
        currency: FundCurrency.usdt, api: api, accountProvider: () => owner);
    addTearDown(controller.dispose);
    controller.setActive(true);
    final flight = controller.load();
    controller.setActive(false);
    owner = 'b';
    pending.complete(depositAddressFixture());
    await flight;
    expect(controller.rule, isNull);
    controller.setActive(true);
    await controller.load();
    expect(controller.isActive, false);
    expect(api.addressCalls, 1);
  });

  test('missing or failed rules block readiness; explicit retry can recover',
      () async {
    final api =
        WalletTestFundApi(address: depositAddressFixture(withRules: false));
    final controller = WalletWithdrawalRulesController(
        currency: FundCurrency.usdt, api: api, accountProvider: () => 'owner');
    addTearDown(controller.dispose);
    controller.setActive(true);
    await controller.load();
    expect(controller.failed, true);
    api.respondAddress = () => Future.error(Exception('offline'));
    await controller.load();
    expect(controller.rule, isNull);
    api.respondAddress = null;
    api.address = depositAddressFixture();
    await controller.load();
    expect(controller.failed, false);
    expect(controller.rule!.isWithdrawalComplete, true);
  });

  test('dispose while awaiting ignores completion without notifying listeners',
      () async {
    final pending = Completer<WalletDepositAddress>();
    final api = WalletTestFundApi()..respondAddress = () => pending.future;
    final controller = WalletWithdrawalRulesController(
        currency: FundCurrency.usdt, api: api, accountProvider: () => 'owner');
    var events = 0;
    controller.addListener(() => events++);
    controller.setActive(true);
    final flight = controller.load();
    expect(events, 1);
    controller.dispose();
    pending.complete(depositAddressFixture());
    await flight;
    expect(events, 1);
  });
}

WalletDepositAddress _address(String fee) => WalletDepositAddress(
      status: 'ready',
      network: 'TRON',
      address: testDepositAddress,
      currencies: const [FundCurrency.usdt],
      confirmations: 19,
      usdtContract: testUsdtContract,
      currencyRules: {
        FundCurrency.usdt: WalletCurrencyRule(
          currency: FundCurrency.usdt,
          minWithdrawAmount: '0.1',
          withdrawFee: fee,
          withdrawFeeCurrency: FundCurrency.usdt,
        )
      },
    );
