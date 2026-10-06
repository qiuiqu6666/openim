import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';
import 'package:openim/pages/wallet/wallet_receive_screen.dart';

import 'support/wallet_deposit_coin_test_support.dart';

void main() {
  testWidgets(
      'only endpoint-supported currencies appear once in the popular list',
      (tester) async {
    final api = WalletTestFundApi(
      address: WalletDepositAddress(
        status: 'ready',
        network: 'TRON',
        address: testDepositAddress,
        currencies: const [FundCurrency.trx],
        confirmations: 19,
        usdtContract: '',
      ),
    );
    await pumpWalletDepositCoins(tester, api: api);
    expect(coinRow('TRX'), findsOneWidget);
    expect(find.text('TRX'), findsOneWidget);
    expect(coinKey('wallet-deposit-coin-all-TRX'), findsNothing);
    expect(coinRow('USDT'), findsNothing);
    expect(coinKey('wallet-deposit-coin-index-T'), findsNothing);
    expect(coinKey('wallet-deposit-coin-index-U'), findsNothing);
    expect(find.text('BI99'), findsNothing);
    expect(api.addressCalls, 1);
    expect(api.balanceCalls, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'pending allocation can list currencies without exposing an address',
      (tester) async {
    final api = WalletTestFundApi(address: depositAddressFixture(ready: false));
    await pumpWalletDepositCoins(tester, api: api);
    expect(coinRow('USDT'), findsOneWidget);
    expect(coinRow('TRX'), findsOneWidget);
    expect(find.text(testDepositAddress), findsNothing);
    expect(coinKey('wallet-deposit-qr'), findsNothing);
    api.address = depositAddressFixture();
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(api.addressCalls, 2);
    expect(coinRow('USDT'), findsOneWidget);
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'real search filters code, name and contract and cancel clears focus',
      (tester) async {
    final api = WalletTestFundApi();
    await pumpWalletDepositCoins(tester, api: api);
    for (final query in [' uSdT ', 'tEtHeR', testUsdtContract.toLowerCase()]) {
      await searchCoins(tester, query);
      expect(coinRow('USDT', searching: true), findsOneWidget);
      expect(coinRow('TRX', searching: true), findsNothing);
      expect(coinKey('wallet-deposit-coin-index-T'), findsNothing);
    }
    await searchCoins(tester, ' tRoN ');
    expect(coinRow('TRX', searching: true), findsOneWidget);
    expect(coinRow('USDT', searching: true), findsNothing);
    await searchCoins(tester, 'unsupported coin');
    expect(coinKey('wallet-deposit-coin-empty'), findsOneWidget);
    expect(find.text('未找到匹配币种'), findsOneWidget);
    expect(coinKey('wallet-deposit-coin-retry'), findsNothing);
    final field =
        tester.widget<TextField>(coinKey('wallet-deposit-coin-search'));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.tap(coinKey('wallet-deposit-coin-cancel'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isFalse);
    expect(coinRow('USDT'), findsOneWidget);
    expect(coinRow('TRX'), findsOneWidget);
    expect(api.addressCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failure uses a retry state; retries remain singleflight',
      (tester) async {
    final api = WalletTestFundApi()
      ..respondAddress =
          () => Future.error(const FormatException('server data'));
    await pumpWalletDepositCoins(tester, api: api);
    expect(coinKey('wallet-deposit-coin-error'), findsOneWidget);
    expect(find.textContaining('server data'), findsNothing);
    expect(coinRow('USDT'), findsNothing);
    await tester.pump(const Duration(seconds: 12));
    expect(api.addressCalls, 1);
    final pending = Completer<WalletDepositAddress>();
    api.respondAddress = () => pending.future;
    final retry =
        tester.widget<TextButton>(coinKey('wallet-deposit-coin-retry'));
    retry.onPressed!();
    retry.onPressed!();
    await tester.pump();
    expect(api.addressCalls, 2);
    expect(coinKey('wallet-deposit-coin-loading'), findsOneWidget);
    pending.complete(depositAddressFixture());
    await tester.pump();
    expect(coinRow('USDT'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final code in ['USDT', 'TRX']) {
    testWidgets(
        'select $code fetches an authenticated address and retains search on back',
        (tester) async {
      final api = WalletTestFundApi();
      final observer = CoinPickerRouteObserver();
      await pumpWalletDepositCoins(tester, api: api, observer: observer);
      await searchCoins(tester, code.toLowerCase());
      await tester.tap(coinRow(code, searching: true));
      await tester.pumpAndSettle();
      expect(observer.routes.last, isA<AppMaterialPageRoute<void>>());
      expect(find.byType(WalletReceiveScreen), findsOneWidget);
      expect(
          tester.widget<Text>(coinKey('wallet-deposit-title-coin')).data, code);
      expect(api.addressCalls, 2);
      expect(coinKey('wallet-deposit-qr'), findsOneWidget);
      expect(coinKey('wallet-deposit-contract-preview'), findsNothing);
      expect(coinKey('wallet-deposit-contract-info'), findsNothing);
      Navigator.of(tester.element(find.byType(WalletReceiveScreen)),
              rootNavigator: true)
          .pop();
      await tester.pumpAndSettle();
      final field =
          tester.widget<TextField>(coinKey('wallet-deposit-coin-search'));
      expect(field.controller!.text, code.toLowerCase());
      expect(coinRow(code, searching: true), findsOneWidget);
      expect(field.focusNode!.hasFocus, isFalse);
      expect(api.addressCalls, 2);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
      'double selection opens one detail and pauses picker pending polling',
      (tester) async {
    final api = WalletTestFundApi(address: depositAddressFixture(ready: false));
    final observer = CoinPickerRouteObserver();
    await pumpWalletDepositCoins(tester, api: api, observer: observer);
    await tester.tap(coinRow('USDT'));
    await tester.tap(coinRow('USDT'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(observer.routes, hasLength(2));
    expect(api.addressCalls, 2);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(api.addressCalls, 3,
        reason:
            'Only the current detail route may poll, never the covered picker');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'a fresh response removing the selected currency never changes the coin',
      (tester) async {
    final api = WalletTestFundApi();
    await pumpWalletDepositCoins(tester, api: api);
    api.address = WalletDepositAddress(
      status: 'ready',
      network: 'TRON',
      address: testDepositAddress,
      currencies: const [FundCurrency.usdt],
      confirmations: 19,
      usdtContract: testUsdtContract,
    );
    await tester.tap(coinRow('TRX'));
    await tester.pumpAndSettle();
    expect(find.byType(WalletReceiveScreen), findsOneWidget);
    expect(find.text('该币种暂不支持充值，请返回重新选择'), findsOneWidget);
    for (final key in [
      'wallet-deposit-qr',
      'wallet-deposit-copy',
      'wallet-deposit-address-copy',
      'wallet-deposit-share'
    ]) {
      expect(coinKey(key), findsNothing);
    }
    expect(
        tester.widget<Text>(coinKey('wallet-deposit-title-coin')).data, 'TRX');
    expect(api.addressCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
