import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';
import 'package:openim/pages/wallet/wallet_receive_screen.dart';

import 'support/wallet_deposit_coin_test_support.dart';

void main() {
  testWidgets('background and covered picker routes do not poll allocation',
      (tester) async {
    final api = WalletTestFundApi(address: depositAddressFixture(ready: false));
    await pumpWalletDepositCoins(tester, api: api);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 1);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(api.addressCalls, 2);
    final navigator = Navigator.of(
        tester.element(coinKey('wallet-deposit-coin-picker')),
        rootNavigator: true);
    navigator.push<void>(AppMaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('cover')),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 2);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(api.addressCalls, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('account changes hide capabilities and block a stale row tap',
      (tester) async {
    var account = 'server:first-user';
    final api = WalletTestFundApi(address: depositAddressFixture(ready: false));
    final observer = CoinPickerRouteObserver();
    await pumpWalletDepositCoins(tester,
        api: api, accountProvider: () => account, observer: observer);
    account = 'server:second-user';
    await tester.tap(coinRow('USDT'));
    await tester.pump();
    expect(find.byType(WalletReceiveScreen), findsNothing);
    expect(observer.routes, hasLength(1));
    await searchCoins(tester, 'usdt');
    expect(coinKey('wallet-deposit-coin-account-changed'), findsOneWidget);
    expect(coinRow('USDT', searching: true), findsNothing);
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late requests cannot restore capabilities after account change',
      (tester) async {
    var account = 'server:first-user';
    final pending = Completer<WalletDepositAddress>();
    final api = WalletTestFundApi()..respondAddress = () => pending.future;
    await pumpWalletDepositCoins(tester,
        api: api, accountProvider: () => account);
    expect(coinKey('wallet-deposit-coin-loading'), findsOneWidget);
    account = 'other-server:first-user';
    pending.complete(depositAddressFixture());
    await tester.pump();
    await searchCoins(tester, 'usdt');
    expect(coinKey('wallet-deposit-coin-account-changed'), findsOneWidget);
    expect(coinRow('USDT', searching: true), findsNothing);
    expect(api.addressCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dispose ignores a late result and cancels all allocation work',
      (tester) async {
    final pending = Completer<WalletDepositAddress>();
    final api = WalletTestFundApi()..respondAddress = () => pending.future;
    await pumpWalletDepositCoins(tester, api: api);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(depositAddressFixture(ready: false));
    await tester.pump(const Duration(seconds: 12));
    expect(tester.takeException(), isNull);
    expect(api.addressCalls, 1);
  });
}
