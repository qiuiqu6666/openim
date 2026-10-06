import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

import 'wallet_home_test_support.dart';

void main() {
  testWidgets('visibility masks total and coin balances, including semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final controller = await loadedHomeController();
    await pumpWalletHome(tester, controller: controller);
    await tester.pumpAndSettle();

    const amounts = ['8,652.48', '1,220.16', '5,800.00', '402.325811'];
    for (final amount in amounts.where((value) => value != '1,220.16')) {
      expect(find.textContaining(amount), findsWidgets);
    }
    expect(find.text(r'$1,220.16'), findsNothing);
    expect(find.text('¥8,652.48'), findsOneWidget);
    await _selectCurrency(tester, 'USD');
    expect(find.text(r'$1,220.16'), findsOneWidget);
    expect(find.text('¥8,652.48'), findsNothing);
    await tester.tap(walletHomeKey('wallet-toggle-balance'));
    await tester.pumpAndSettle();
    expect(controller.showBal, isFalse);
    for (final currency in ['CNY', 'USD']) {
      await _selectCurrency(tester, currency);
      final spoken = tester
          .getSemantics(walletHomeKey('wallet-home-scroll'))
          .toStringDeep();
      for (final amount in amounts) {
        expect(find.textContaining(amount), findsNothing);
        expect(spoken, isNot(contains(amount)),
            reason: 'Hidden amount was spoken after switching to $currency');
      }
      expect(tester.widget<Text>(walletHomeKey('wallet-daily-profit')).data,
          '••••••');
    }
    expect(find.text('USDT'), findsWidgets);
    await tester.tap(walletHomeKey('wallet-toggle-balance'));
    await tester.pumpAndSettle();
    expect(controller.showBal, isTrue);
    expect(find.text(r'$1,220.16'), findsOneWidget);
    expect(find.textContaining('402.325811'), findsWidgets);
    semantics.dispose();
  });

  testWidgets('currency menu uses only available repository totals',
      (tester) async {
    final controller = await loadedHomeController();
    await pumpWalletHome(tester, controller: controller);
    await tester.pumpAndSettle();
    expect(find.text('¥8,652.48'), findsOneWidget);
    expect(walletHomeKey('wallet-usd-amount'), findsNothing);
    await _selectCurrency(tester, 'USD');
    expect(find.text(r'$1,220.16'), findsOneWidget);
    await _selectCurrency(tester, 'CNY');
    expect(find.text('¥8,652.48'), findsOneWidget);
    expect(controller.totalBal, walletHomeFixture.totalBal);
    expect(controller.totalBalUsd, walletHomeFixture.totalBalUsd);
  });

  for (final data in [
    walletHomeFilterFixture,
    const WalletDto(
        totalBal: '18.25', totalBalUsd: '   ', trxAddr: '', coins: []),
  ]) {
    testWidgets('missing USD total offers only CNY for ${data.totalBal}',
        (tester) async {
      final controller = await loadedHomeController(
          repository: HomeTestRepository(data: data));
      await pumpWalletHome(tester, controller: controller);
      await tester.pumpAndSettle();
      await tester.tap(walletHomeKey('wallet-display-currency'));
      await tester.pumpAndSettle();
      expect(_currencyItem('CNY'), findsOneWidget);
      expect(_currencyItem('USD'), findsNothing);
      await tester.tap(_currencyItem('CNY'));
      await tester.pumpAndSettle();
      expect(find.text('¥${data.totalBal}'), findsOneWidget);
      expect(find.textContaining(r'$'), findsNothing,
          reason: 'The UI must not invent a currency conversion.');
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('daily profit stays unknown and noninteractive in $brightness',
        (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final controller = await loadedHomeController();
        final observer = HomeRouteObserver();
        await pumpWalletHome(tester,
            controller: controller, observer: observer, brightness: brightness);
        await tester.pumpAndSettle();
        final row = walletHomeKey('wallet-daily-profit-row');
        final amount = walletHomeKey('wallet-daily-profit');
        final label = find.descendant(of: row, matching: find.text('今日盈亏'));
        expect(tester.widget<Text>(amount).data, '-- (--%)');
        expect(tester.getRect(row).height, greaterThanOrEqualTo(48));
        expect(find.descendant(of: row, matching: find.byType(Icon)),
            findsNothing);
        expect(tester.widget<Text>(label).style?.decoration,
            anyOf(isNull, TextDecoration.none));
        for (final target in [amount, label]) {
          final data = tester.getSemantics(target).getSemanticsData();
          expect(data.hasAction(SemanticsAction.tap), isFalse);
          expect(data.flagsCollection.isButton, isFalse);
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(observer.lastPush, isNull);
          expect(tester.widget<Text>(amount).data, '-- (--%)');
        }
        expect(find.text('¥0.00'), findsNothing);
        expect(find.text('0.00%'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }

  testWidgets('value sorting retains unknown valuations', (tester) async {
    final controller = await loadedHomeController(
      repository: HomeTestRepository(data: walletHomeFilterFixture),
    );
    await pumpWalletHome(tester, controller: controller);
    await tester.pumpAndSettle();
    expect(find.text('Small asset'), findsOneWidget);
    await tester.ensureVisible(walletHomeKey('wallet-assets-filter'));
    await tester.tap(walletHomeKey('wallet-assets-filter'));
    await tester.pumpAndSettle();
    expect(find.text('Small asset'), findsOneWidget);
    expect(find.text('Known holding'), findsOneWidget);
    expect(find.text('Unknown valuation'), findsOneWidget);
    await tester.tap(walletHomeKey('wallet-assets-filter'));
    await tester.pumpAndSettle();
    expect(find.text('Small asset'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'failed first load retries by pull refresh with progress in $brightness',
        (tester) async {
      final repository = HomeTestRepository()
        ..respond =
            () => Future.error(const WalletBackendUnavailableException());
      final controller = await loadedHomeController(repository: repository);
      await pumpWalletHome(tester,
          controller: controller, brightness: brightness);
      await tester.pumpAndSettle();
      _expectNoFailureNotice();
      expect(repository.walletCalls, 1);
      final pending = Completer<WalletDto>();
      repository.respond = () => pending.future;
      await _startPullRefresh(tester);
      expect(repository.walletCalls, 2);
      expect(controller.loading, isTrue);
      expect(walletHomeKey('wallet-home-loading'), findsOneWidget);
      _expectNoFailureNotice();
      pending.complete(walletHomeFixture);
      await tester.pumpAndSettle();
      expect(walletHomeKey('wallet-home-loading'), findsNothing);
      expect(find.textContaining('8,652.48'), findsWidgets);
      _expectNoFailureNotice();
    });

    testWidgets(
        'initial loading resolves without invented balance in $brightness',
        (tester) async {
      final pending = Completer<WalletDto>();
      final repository = HomeTestRepository()..respond = () => pending.future;
      final controller = WalletController(repo: repository);
      addTearDown(controller.dispose);
      final loading = controller.load();
      await pumpWalletHome(tester,
          controller: controller, brightness: brightness);
      expect(walletHomeKey('wallet-home-loading'), findsOneWidget);
      expect(find.textContaining('8,652.48'), findsNothing);
      expect(repository.walletCalls, 1,
          reason: 'The view must not duplicate lifecycle-owned requests');
      pending.complete(walletHomeFixture);
      await tester.pump();
      await loading;
      await tester.pumpAndSettle();
      expect(walletHomeKey('wallet-home-loading'), findsNothing);
      expect(find.textContaining('8,652.48'), findsWidgets);
    });

    testWidgets('empty server result has a real empty state in $brightness',
        (tester) async {
      final controller = await loadedHomeController(
        repository: HomeTestRepository(
            data: const WalletDto(
          totalBal: '0.00',
          trxAddr: '',
          coins: [],
        )),
      );
      await pumpWalletHome(tester,
          controller: controller, brightness: brightness);
      await tester.pumpAndSettle();
      expect(walletHomeKey('wallet-home-empty'), findsOneWidget);
      expect(walletHomeKey('wallet-refresh-error'), findsNothing);
      expect(find.text('USDT'), findsNothing);
    });

    testWidgets(
        'initial failure stays quiet and pull refresh retries in $brightness',
        (tester) async {
      final repository = HomeTestRepository()
        ..respond =
            () => Future.error(const WalletBackendUnavailableException());
      final controller = await loadedHomeController(repository: repository);
      await pumpWalletHome(tester,
          controller: controller, brightness: brightness);
      await tester.pumpAndSettle();
      _expectNoFailureNotice();
      expect(repository.walletCalls, 1);
      expect(controller.totalBal, '--');
      expect(tester.widget<Text>(walletHomeKey('wallet-total-amount')).data,
          '¥--');
      expect(find.textContaining('8,652.48'), findsNothing);
      expect(find.text('¥0.00'), findsNothing,
          reason: 'A failed request must retain unknown amounts.');
      repository.respond = () => Future.value(walletHomeFixture);
      await _startPullRefresh(tester);
      await tester.pumpAndSettle();
      expect(repository.walletCalls, 2);
      _expectNoFailureNotice();
      expect(find.textContaining('8,652.48'), findsWidgets);
    });

    testWidgets(
        'refresh failure quietly retains snapshot and supports another pull in $brightness',
        (tester) async {
      final repository = HomeTestRepository();
      final controller = await loadedHomeController(repository: repository);
      await pumpWalletHome(tester,
          controller: controller, brightness: brightness);
      await tester.pumpAndSettle();
      repository.respond =
          () => Future.error(const WalletBackendUnavailableException());
      await _startPullRefresh(tester);
      await tester.pumpAndSettle();
      expect(repository.walletCalls, 2);
      _expectNoFailureNotice();
      expect(find.textContaining('8,652.48'), findsWidgets);
      expect(find.textContaining('402.325811'), findsWidgets);
      expect(walletHomeKey('wallet-home-empty'), findsNothing);
      repository.respond = () => Future.value(walletHomeFixture);
      await _startPullRefresh(tester);
      await tester.pumpAndSettle();
      expect(repository.walletCalls, 3);
      _expectNoFailureNotice();
      expect(find.textContaining('8,652.48'), findsWidgets);
      expect(find.textContaining('402.325811'), findsWidgets);
    });
  }

  testWidgets(
      'pull refresh reloads once and preserves hidden amounts and filter',
      (tester) async {
    final repository = HomeTestRepository(data: walletHomeFilterFixture);
    final controller = await loadedHomeController(repository: repository);
    await pumpWalletHome(tester, controller: controller);
    await tester.pumpAndSettle();
    await tester.tap(walletHomeKey('wallet-toggle-balance'));
    await tester.tap(walletHomeKey('wallet-assets-filter'));
    await tester.pumpAndSettle();
    await tester.drag(
        walletHomeKey('wallet-home-scroll'), const Offset(0, 420));
    await tester.pumpAndSettle();
    expect(repository.walletCalls, 2);
    expect(controller.showBal, isFalse);
    expect(find.textContaining('10.10'), findsNothing);
    expect(find.text('Small asset'), findsOneWidget);
    expect(find.text('Unknown valuation'), findsOneWidget);
  });

  testWidgets('pulling the blank space below compact assets refreshes wallet',
      (tester) async {
    final repository = HomeTestRepository();
    final controller = await loadedHomeController(repository: repository);
    await pumpWalletHome(tester,
        controller: controller, size: const Size(390, 844));
    await tester.pumpAndSettle();
    const start = Offset(195, 764);
    expect(
        start.dy,
        greaterThan(
            tester.getRect(walletHomeKey('wallet-assets-section')).bottom),
        reason: 'The gesture must start in blank space, below all wallet rows');
    await tester.dragFrom(start, const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(repository.walletCalls, 2,
        reason: 'The entire available viewport should accept pull to refresh');
    expect(find.textContaining('8,652.48'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resize between phone and wide layout retains asset filter',
      (tester) async {
    final repository = HomeTestRepository(data: walletHomeFilterFixture);
    final controller = await loadedHomeController(repository: repository);
    await pumpWalletHome(tester,
        controller: controller, size: const Size(320, 844));
    await tester.pumpAndSettle();
    await tester.tap(walletHomeKey('wallet-assets-filter'));
    await tester.pumpAndSettle();
    expect(find.text('Small asset'), findsOneWidget);
    await pumpWalletHome(tester,
        controller: controller, size: const Size(900, 844));
    await tester.pumpAndSettle();
    expect(find.text('Small asset'), findsOneWidget);
    expect(find.text('Unknown valuation'), findsOneWidget);
    expect(repository.walletCalls, 1);
    expect(tester.takeException(), isNull);
  });
}

Finder _currencyItem(String currency) => find.byWidgetPredicate(
    (widget) => widget is PopupMenuItem<String> && widget.value == currency);

Future<void> _selectCurrency(WidgetTester tester, String currency) async {
  await tester.tap(walletHomeKey('wallet-display-currency'));
  await tester.pumpAndSettle();
  await tester.tap(_currencyItem(currency));
  await tester.pumpAndSettle();
}

void _expectNoFailureNotice() {
  expect(walletHomeKey('wallet-refresh-error'), findsNothing);
  expect(walletHomeKey('wallet-retry'), findsNothing);
}

Future<void> _startPullRefresh(WidgetTester tester) async {
  await tester.drag(walletHomeKey('wallet-home-scroll'), const Offset(0, 420));
  await tester.pump();
  // Let the indicator finish snapping before checking a pending repository
  // call; settling is inappropriate while its loading animation is active.
  await tester.pump(const Duration(milliseconds: 300));
}
