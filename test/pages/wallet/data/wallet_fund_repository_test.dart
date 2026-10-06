import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/data/wallet_session_source.dart';
import 'package:openim/pages/wallet/record/wallet_record_models.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';

import 'wallet_fund_test_api.dart';

void main() {
  test(
      'real balance adapter rounds only presentation and excludes frozen funds',
      () async {
    final api = WalletTestFundApi();
    final repository =
        WalletFundRepository(api: api, accountProvider: () => 'server:user');
    final snapshot = await repository.getWallet();
    expect(snapshot.coins.map((coin) => coin.code), ['USDT', 'TRX', '99']);
    expect(snapshot.coins.map((coin) => coin.bal), ['12.35', '8.01', '9.00']);
    final usdt = snapshot.coins.first;
    expect(usdt.availableRaw, '12.345678');
    expect(usdt.frozen, '4.1');
    expect(usdt.balMinor, 12345678);
    expect(snapshot.totalBal, '--');
    expect(snapshot.totalBalUsd, isEmpty);
    expect(snapshot.trxAddr, isEmpty);
    expect(
        snapshot.coins.every((coin) => coin.fiat == '--' && coin.sub == '--'),
        isTrue);
    expect(snapshot.coins.last.depositEnabled, isFalse);
    expect(snapshot.coins.first.depositEnabled, isTrue);
    expect(api.balanceCalls, 1);
    expect(api.addressCalls, 0);
  });

  test('negative balances and oversized precision are not clamped or truncated',
      () async {
    final api = WalletTestFundApi(balances: balancesFixture(usdt: '-0.015001'));
    final repository =
        WalletFundRepository(api: api, accountProvider: () => 'server:user');
    var coin = (await repository.getWallet()).coins.first;
    expect(coin.availableRaw, '-0.015001');
    expect(coin.bal, '-0.02');
    expect(coin.balMinor, -15001);
    api.balances = balancesFixture(usdt: '123456789012345678.123456');
    coin = (await repository.getWallet()).coins.first;
    expect(coin.availableRaw, '123456789012345678.123456');
    expect(coin.bal, '123456789012345678.12');
    expect(coin.withdrawEnabled, isFalse);
    expect(coin.balMinor, 0);
  });

  test('all deposit events survive identical tx hashes without made-up times',
      () async {
    final api = WalletTestFundApi();
    final repository =
        WalletFundRepository(api: api, accountProvider: () => 'server:user');
    final records = await repository.getDepositRecords();
    expect(records, hasLength(3));
    expect(records.map((record) => record.id).toSet(), hasLength(3));
    expect(
        records.take(2).map((record) => record.hash), ['same-tx', 'same-tx']);
    expect(
        records.every((record) =>
            record.time.isEmpty &&
            record.orderNo.isEmpty &&
            record.fee.isEmpty),
        isTrue);
    expect(records.first.amount, '12.345678');
    expect(records.first.addr, testDepositAddress);
    expect(records.last.status, WalletRecordStatus.failed);
    expect(records.last.income, isFalse);
    expect(await repository.getWithdrawRecords(), isEmpty);
    expect(repository.hasCompleteLedger, isFalse);
    expect(repository.hasWithdrawalHistory, isFalse);
    expect(repository.depositRecordLimit, 100);
    expect(api.depositCalls, 1);
  });

  test('late account response cannot publish old-owner balances', () async {
    var account = 'server:old';
    final pending = Completer<List<FundBalance>>();
    final api = WalletTestFundApi()..respondBalances = () => pending.future;
    final repository =
        WalletFundRepository(api: api, accountProvider: () => account);
    final future = repository.getWallet();
    final assertion =
        expectLater(future, throwsA(isA<WalletAccountChangedException>()));
    account = 'server:new';
    pending.complete(balancesFixture());
    await assertion;
    await expectLater(repository.getDepositRecords(),
        throwsA(isA<WalletAccountChangedException>()));
    expect(api.depositCalls, 0);
  });

  test(
      'controller refresh events are scoped, coalesced and deferred while inactive',
      () async {
    final events = StreamController<String>.broadcast(sync: true);
    final api = WalletTestFundApi();
    var account = 'server:user';
    final repository =
        WalletFundRepository(api: api, accountProvider: () => account);
    final controller =
        WalletController(repo: repository, balanceChanges: events.stream);
    await controller.load();
    controller.setActive(false);
    events.add('server:other');
    expect(controller.hasDeferredRefresh, isFalse);
    events.add(account);
    events.add(account);
    expect(controller.hasDeferredRefresh, isTrue);
    expect(api.balanceCalls, 1);
    controller.setActive(true);
    await Future<void>.delayed(Duration.zero);
    expect(api.balanceCalls, 2);
    expect(controller.hasDeferredRefresh, isFalse);
    account = 'server:new';
    events.add('server:user');
    await controller.load();
    expect(api.balanceCalls, 2);
    expect(controller.coins, isEmpty);
    expect(controller.totalBal, '--');
    controller.dispose();
    events.add(account);
    await events.close();
  });
}
