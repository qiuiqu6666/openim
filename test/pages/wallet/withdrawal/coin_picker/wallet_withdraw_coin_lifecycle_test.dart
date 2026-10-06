import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';
import 'package:openim/pages/wallet/order/wallet_order_events.dart';

import 'support/wallet_withdraw_coin_test_support.dart';

void main() {
  testWidgets('account changes block an old tap and hide previous balances',
      (tester) async {
    final repository = WithdrawSessionTestRepository();
    final observer = WithdrawCoinRouteObserver();
    await pumpWalletWithdrawCoins(tester,
        repository: repository, observer: observer);
    final oldTap = withdrawCoinCallback(tester, withdrawCoinRow('USDT'));
    repository.currentAccountKey = 'fixture-other-server:withdraw-user';
    oldTap();
    await tester.pump();
    expect(observer.detailPushes, 0);
    await searchWithdrawCoins(tester, 'usdt');
    expect(withdrawCoinKey('account-changed'), findsOneWidget);
    expect(withdrawCoinRow('USDT', section: 'search'), findsNothing);
    WalletOrderEvents.notifyBalance(accountKey: repository.ownerAccountKey);
    await tester.pump();
    expect(repository.walletCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a late account response cannot publish selectable balances',
      (tester) async {
    final pending = Completer<WalletDto>();
    final repository = WithdrawSessionTestRepository()
      ..respond = () => pending.future;
    await pumpWalletWithdrawCoins(tester, repository: repository);
    expect(withdrawCoinKey('loading'), findsOneWidget);
    repository.currentAccountKey = 'fixture-server:another-user';
    pending.complete(withdrawWalletFixture());
    await tester.pump();
    await searchWithdrawCoins(tester, 'usdt');
    expect(withdrawCoinKey('account-changed'), findsOneWidget);
    expect(withdrawCoinRow('USDT', section: 'search'), findsNothing);
    expect(find.text('12.35'), findsNothing);
    expect(repository.walletCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('background defers balance refresh and blocks captured taps',
      (tester) async {
    final repository = WithdrawSessionTestRepository();
    final observer = WithdrawCoinRouteObserver();
    await pumpWalletWithdrawCoins(tester,
        repository: repository, observer: observer);
    final oldTap = withdrawCoinCallback(tester, withdrawCoinRow('USDT'));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      WalletOrderEvents.notifyBalance(accountKey: repository.ownerAccountKey);
      await tester.pump();
      oldTap();
    }
    expect(repository.walletCalls, 1);
    expect(observer.detailPushes, 0);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump();
    expect(repository.walletCalls, 2);
    expect(withdrawCoinRow('USDT'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('covered route defers refresh and preserves search after return',
      (tester) async {
    final repository = WithdrawSessionTestRepository();
    final observer = WithdrawCoinRouteObserver();
    await pumpWalletWithdrawCoins(tester,
        repository: repository, observer: observer);
    await searchWithdrawCoins(tester, 'tether');
    final oldTap = withdrawCoinCallback(
        tester, withdrawCoinRow('USDT', section: 'search'));
    observer.navigator!.push<void>(AppMaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered fixture route'))));
    await tester.pumpAndSettle();
    final pushesBeforeTap = observer.detailPushes;
    WalletOrderEvents.notifyBalance(accountKey: repository.ownerAccountKey);
    await tester.pump();
    oldTap();
    expect(repository.walletCalls, 1);
    expect(observer.detailPushes, pushesBeforeTap);
    observer.navigator!.pop();
    await tester.pumpAndSettle();
    expect(repository.walletCalls, 2);
    expect(tester.widget<TextField>(withdrawCoinKey('search')).controller!.text,
        'tether');
    expect(withdrawCoinRow('USDT', section: 'search'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('resume hides a changed account without a balance event or edit',
      (tester) async {
    final repository = WithdrawSessionTestRepository();
    await pumpWalletWithdrawCoins(tester, repository: repository);
    expect(withdrawCoinRow('USDT'), findsOneWidget);
    expect(find.text('12.35'), findsWidgets);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    repository.currentAccountKey = 'fixture-server:another-user';
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(withdrawCoinKey('account-changed'), findsOneWidget);
    expect(withdrawCoinRow('USDT'), findsNothing);
    expect(withdrawCoinRow('TRX'), findsNothing);
    expect(withdrawCoinRow('99'), findsNothing);
    expect(find.text('12.35'), findsNothing);
    expect(find.text('¥87.53'), findsNothing);
    expect(repository.walletCalls, 1,
        reason: 'Returning must not request balances for the new account');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'route return hides a changed account without notification or edit',
      (tester) async {
    final repository = WithdrawSessionTestRepository();
    final observer = WithdrawCoinRouteObserver();
    await pumpWalletWithdrawCoins(tester,
        repository: repository, observer: observer);
    expect(withdrawCoinRow('USDT'), findsOneWidget);
    expect(find.text('12.35'), findsWidgets);
    observer.navigator!.push<void>(AppMaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered fixture route'))));
    await tester.pumpAndSettle();
    repository.currentAccountKey = 'fixture-other-server:withdraw-user';
    observer.navigator!.pop();
    await tester.pumpAndSettle();
    expect(withdrawCoinKey('account-changed'), findsOneWidget);
    expect(withdrawCoinRow('USDT'), findsNothing);
    expect(withdrawCoinRow('TRX'), findsNothing);
    expect(withdrawCoinRow('99'), findsNothing);
    expect(find.text('12.35'), findsNothing);
    expect(find.text('¥87.53'), findsNothing);
    expect(repository.walletCalls, 1,
        reason: 'Returning must not request balances for the new account');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unrelated account balance events never refresh this picker',
      (tester) async {
    final repository = WithdrawSessionTestRepository();
    await pumpWalletWithdrawCoins(tester, repository: repository);
    WalletOrderEvents.notifyBalance(accountKey: 'fixture-server:other-user');
    await tester.pump();
    expect(repository.walletCalls, 1);
    WalletOrderEvents.notifyBalance(accountKey: repository.ownerAccountKey);
    await tester.pump();
    await tester.pump();
    expect(repository.walletCalls, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('old row callbacks use fresh exact units and respect revocation',
      (tester) async {
    final repository = WithdrawSessionTestRepository();
    final observer = WithdrawCoinRouteObserver();
    // Internal withdrawals now open a form; this case verifies chain coin DTOs.
    await pumpWalletWithdrawCoins(tester,
        repository: repository,
        observer: observer,
        kind: WithdrawTransferTargetKind.chain);
    final oldTap = withdrawCoinCallback(tester, withdrawCoinRow('USDT'));
    const updatedUsdt = CoinDto(
      name: 'Backend stable token',
      code: 'USDT',
      sub: '¥7.09',
      bal: '27.65',
      fiat: '¥196.06',
      type: CoinType.usdt,
      balMinor: 27654321,
      scale: 6,
      availableRaw: '27.654321',
      frozen: '6.2',
    );
    repository.respond = () => Future.value(withdrawWalletFixture(coins: const [
          updatedUsdt,
          withdrawTrxFixture,
          withdrawPlatformFixture,
        ]));
    WalletOrderEvents.notifyBalance(accountKey: repository.ownerAccountKey);
    await tester.pump();
    await tester.pump();
    expect(repository.walletCalls, 2);
    oldTap();
    expect(observer.detailPushes, 1);
    final page = inspectWithdrawDestination(tester, observer);
    expect(identical(page.coin, updatedUsdt), isTrue);
    expect(page.coin.availableRaw, '27.654321');
    expect(page.coin.frozen, '6.2');
    expect(page.payMethod.balMinor, 27654321);
    expect(page.payMethod.scale, 6);
    expect(page.payMethod.bal, '27.65');
    expect(page.payMethod.fiat, '¥196.06');
    await removeWithdrawDestination(tester, observer);

    const revokedUsdt = CoinDto(
      name: 'Backend stable token',
      code: 'USDT',
      sub: '¥7.09',
      bal: '27.65',
      fiat: '¥196.06',
      type: CoinType.usdt,
      balMinor: 27654321,
      scale: 6,
      availableRaw: '27.654321',
      frozen: '6.2',
      withdrawEnabled: false,
    );
    repository.respond = () => Future.value(withdrawWalletFixture(coins: const [
          revokedUsdt,
          withdrawTrxFixture,
          withdrawPlatformFixture,
        ]));
    WalletOrderEvents.notifyBalance(accountKey: repository.ownerAccountKey);
    await tester.pump();
    await tester.pump();
    expect(repository.walletCalls, 3);
    expect(withdrawCoinRow('USDT'), findsNothing);
    oldTap();
    expect(observer.detailPushes, 1,
        reason: 'Revoked withdrawal permission also blocks old row callbacks');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposed picker ignores late requests and captured taps',
      (tester) async {
    final pending = Completer<WalletDto>();
    final repository = WithdrawSessionTestRepository()
      ..respond = () => pending.future;
    await pumpWalletWithdrawCoins(tester, repository: repository);
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(withdrawWalletFixture());
    WalletOrderEvents.notifyBalance(accountKey: repository.ownerAccountKey);
    await tester.pump(const Duration(seconds: 7));
    expect(repository.walletCalls, 1);
    expect(tester.takeException(), isNull);
  });
}
