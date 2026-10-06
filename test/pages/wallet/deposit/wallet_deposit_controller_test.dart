import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/deposit/wallet_deposit_controller.dart';

import '../data/wallet_fund_test_api.dart';

void main() {
  testWidgets('pending polls every four seconds without overlapping requests',
      (tester) async {
    final api = WalletTestFundApi(address: depositAddressFixture(ready: false));
    final controller =
        WalletDepositController(api: api, accountProvider: () => 'server:user');
    controller.setActive(true);
    await tester.pump();
    expect(api.addressCalls, 1);
    expect(controller.address!.status, 'pending');
    controller.setActive(true);
    await tester.pump(const Duration(milliseconds: 3999));
    expect(api.addressCalls, 1);
    final pending = Completer<WalletDepositAddress>();
    api.respondAddress = () => pending.future;
    await tester.pump(const Duration(milliseconds: 1));
    expect(api.addressCalls, 2);
    await controller.load();
    await tester.pump(const Duration(seconds: 4));
    expect(api.addressCalls, 2);
    pending.complete(depositAddressFixture());
    await tester.pump();
    expect(controller.canUseAddress, isTrue);
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 2);
    controller.dispose();
  });

  testWidgets(
      'suspension and account changes stop polling and reject late addresses',
      (tester) async {
    var account = 'server:old';
    final pending = Completer<WalletDepositAddress>();
    final api = WalletTestFundApi()..respondAddress = () => pending.future;
    final controller =
        WalletDepositController(api: api, accountProvider: () => account);
    controller.setActive(true);
    controller.setActive(false);
    pending.complete(depositAddressFixture());
    await tester.pump();
    expect(controller.address, isNull);
    await tester.pump(const Duration(seconds: 8));
    expect(api.addressCalls, 1);
    api.respondAddress = null;
    controller.setActive(true);
    await tester.pump();
    expect(controller.canUseAddress, isTrue);
    account = 'server:new';
    expect(controller.address, isNull);
    expect(controller.canUseAddress, isFalse);
    await controller.load();
    expect(api.addressCalls, 2);
    controller.dispose();
  });

  testWidgets(
      'disabled platform deposits make no request and failures allow a manual retry',
      (tester) async {
    final api = WalletTestFundApi();
    final disabled = WalletDepositController(
        api: api, accountProvider: () => 'server:user', enabled: false);
    disabled.setActive(true);
    await disabled.load();
    expect(api.addressCalls, 0);
    disabled.dispose();
    api.respondAddress =
        () async => throw const FormatException('Bad response');
    final controller =
        WalletDepositController(api: api, accountProvider: () => 'server:user');
    controller.setActive(true);
    await tester.pump();
    expect(controller.failed, isTrue);
    expect(controller.failureMessage, '资金数据异常，请稍后重试');
    await tester.pump(const Duration(seconds: 8));
    expect(api.addressCalls, 1);
    api.respondAddress = null;
    await controller.load();
    expect(controller.canUseAddress, isTrue);
    controller.dispose();
  });
}
