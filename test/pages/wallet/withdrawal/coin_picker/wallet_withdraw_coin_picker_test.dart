import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/services/fund_models.dart';

import 'support/wallet_withdraw_coin_test_support.dart';

void main() {
  testWidgets(
      'friend currencies preserve platform coin and hide disabled coins',
      (tester) async {
    final repository = HomeTestRepository(data: withdrawWalletFixture());
    await pumpWalletWithdrawCoins(tester, repository: repository);
    expect(withdrawCoinRow('USDT'), findsOneWidget);
    expect(withdrawCoinRow('TRX'), findsOneWidget);
    expect(withdrawCoinRow('99'), findsOneWidget);
    for (final code in ['USDT', 'TRX', '99']) {
      expect(find.text(code), findsOneWidget);
      expect(withdrawCoinKey('all-$code'), findsNothing);
    }
    expect(withdrawCoinKey('index-T'), findsNothing);
    expect(withdrawCoinKey('index-U'), findsNothing);
    expect(find.text('LOCKED'), findsNothing);
    final usdt = withdrawCoinRow('USDT');
    expect(find.descendant(of: usdt, matching: find.text('12.35')),
        findsOneWidget);
    expect(find.descendant(of: usdt, matching: find.text('¥87.53')),
        findsOneWidget);
    expect(repository.walletCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('chain list accepts supported enabled currencies only',
      (tester) async {
    final repository = HomeTestRepository(
        data: withdrawWalletFixture(coins: const [
      withdrawUsdtFixture,
      withdrawPlatformFixture,
      CoinDto(
        name: 'TRX',
        code: 'TRX',
        sub: '--',
        bal: '8',
        fiat: '--',
        type: CoinType.trx,
        withdrawEnabled: false,
      ),
      CoinDto(
        name: 'Other chain',
        code: 'OTHER',
        sub: '--',
        bal: '8',
        fiat: '--',
        type: CoinType.trx,
      ),
    ]));
    await pumpWalletWithdrawCoins(tester,
        repository: repository, kind: WithdrawTransferTargetKind.chain);
    expect(withdrawCoinRow('USDT'), findsOneWidget);
    expect(withdrawCoinRow('TRX'), findsNothing);
    expect(withdrawCoinRow('99'), findsNothing);
    expect(find.text('OTHER'), findsNothing);
    expect(withdrawCoinKey('index-U'), findsNothing);
    expect(withdrawCoinKey('index-T'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('search matches code, backend name and localized display name',
      (tester) async {
    final repository = HomeTestRepository(data: withdrawWalletFixture());
    await pumpWalletWithdrawCoins(tester, repository: repository);
    for (final query in [' uSdT ', 'tEtHeR', 'BACKEND STABLE']) {
      await searchWithdrawCoins(tester, query);
      expect(withdrawCoinRow('USDT', section: 'search'), findsOneWidget);
      expect(withdrawCoinRow('TRX', section: 'search'), findsNothing);
      expect(withdrawCoinKey('index-T'), findsNothing);
    }
    await searchWithdrawCoins(tester, 'tRoN');
    expect(withdrawCoinRow('TRX', section: 'search'), findsOneWidget);
    expect(withdrawCoinRow('USDT', section: 'search'), findsNothing);
    for (final query in ['平台币', 'Backend reward', '99']) {
      await searchWithdrawCoins(tester, query);
      expect(withdrawCoinRow('99', section: 'search'), findsOneWidget);
      expect(withdrawCoinRow('USDT', section: 'search'), findsNothing);
    }
    await searchWithdrawCoins(tester, 'unknown currency');
    expect(withdrawCoinKey('empty'), findsOneWidget);
    expect(withdrawCoinKey('retry'), findsNothing);
    final field = tester.widget<TextField>(withdrawCoinKey('search'));
    expect(field.focusNode!.hasFocus, isTrue);
    await tester.tap(withdrawCoinKey('cancel'));
    await tester.pumpAndSettle();
    expect(field.controller!.text, isEmpty);
    expect(field.focusNode!.hasFocus, isFalse);
    expect(withdrawCoinRow('USDT'), findsOneWidget);
    expect(repository.walletCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('an empty successful wallet has no selectable fabricated rows',
      (tester) async {
    await pumpWalletWithdrawCoins(tester,
        repository:
            HomeTestRepository(data: withdrawWalletFixture(coins: const [])));
    expect(withdrawCoinKey('empty'), findsOneWidget);
    expect(withdrawCoinKey('error'), findsNothing);
    expect(withdrawCoinRow('USDT'), findsNothing);
    expect(withdrawCoinRow('99'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'initial errors hide fallback rows and retry remains singleflight',
      (tester) async {
    final repository = HomeTestRepository(data: withdrawWalletFixture())
      ..respond =
          () => Future.error(const FormatException('raw server detail'));
    await pumpWalletWithdrawCoins(tester, repository: repository);
    expect(withdrawCoinKey('error'), findsOneWidget);
    expect(withdrawCoinRow('USDT'), findsNothing);
    expect(withdrawCoinRow('99'), findsNothing);
    expect(find.textContaining('raw server detail'), findsNothing);
    final pending = Completer<WalletDto>();
    repository.respond = () => pending.future;
    final retry = tester.widget<TextButton>(withdrawCoinKey('retry'));
    retry.onPressed!();
    retry.onPressed!();
    await tester.pump();
    expect(repository.walletCalls, 2);
    expect(withdrawCoinKey('loading'), findsOneWidget);
    pending.complete(withdrawWalletFixture());
    await tester.pump();
    expect(withdrawCoinRow('USDT'), findsOneWidget);
    expect(withdrawCoinKey('error'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final kind in WithdrawTransferTargetKind.values) {
    testWidgets(
        '$kind selection preserves exact route data and draft on return',
        (tester) async {
      final repository = HomeTestRepository(data: withdrawWalletFixture());
      final observer = WithdrawCoinRouteObserver();
      await pumpWalletWithdrawCoins(tester,
          repository: repository, observer: observer, kind: kind);
      await searchWithdrawCoins(tester, 'stable');
      final onTap = withdrawCoinCallback(
          tester, withdrawCoinRow('USDT', section: 'search'));
      onTap();
      onTap();
      expect(observer.detailPushes, 1);
      if (kind == WithdrawTransferTargetKind.friend) {
        final page = inspectInternalTransferDestination(tester, observer);
        expect(page.isRedPacket, isFalse);
        expect(page.internalWithdrawal, isTrue);
        expect(page.initialCurrency, FundCurrency.usdt);
        expect(page.userID, isNull);
      } else {
        final page = inspectWithdrawDestination(tester, observer);
        expect(page.initialAddress, isEmpty);
        expect(identical(page.coin, withdrawUsdtFixture), isTrue);
        expect(page.coin.availableRaw, '12.345678');
        expect(page.coin.frozen, '4.1');
        expect(page.payMethod.balMinor, 12345678);
        expect(page.payMethod.scale, 6);
        expect(page.payMethod.bal, '12.35');
        expect(page.payMethod.fiat, '¥87.53');
      }
      await removeWithdrawDestination(tester, observer);
      final search = tester.widget<TextField>(withdrawCoinKey('search'));
      expect(search.controller!.text, 'stable');
      expect(search.focusNode!.hasFocus, isFalse);
      expect(withdrawCoinRow('USDT', section: 'search'), findsOneWidget);
      expect(repository.walletCalls, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final entry in [
    (code: '99', currency: FundCurrency.bi99),
    (code: 'TRX', currency: FundCurrency.trx),
  ]) {
    testWidgets(
        'friend ${entry.code} selection opens the selected transfer currency',
        (tester) async {
      final observer = WithdrawCoinRouteObserver();
      await pumpWalletWithdrawCoins(tester, observer: observer);
      await searchWithdrawCoins(tester, entry.code);
      await tester.tap(withdrawCoinRow(entry.code, section: 'search'));
      final page = inspectInternalTransferDestination(tester, observer);
      expect(page.isRedPacket, isFalse);
      expect(page.internalWithdrawal, isTrue);
      expect(page.initialCurrency, entry.currency);
      await removeWithdrawDestination(tester, observer);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
