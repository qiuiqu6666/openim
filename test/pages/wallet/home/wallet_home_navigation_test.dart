import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/deposit/coin_picker/wallet_deposit_coin_picker_screen.dart';
import 'package:openim/pages/wallet/home/wallet_home_view.dart';
import 'package:openim/pages/wallet/home/widgets/wallet_home_action.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';
import 'package:openim/pages/wallet/record/wallet_record_screen.dart';
import 'package:openim/pages/wallet/wallet_exchange_screen.dart';
import 'package:openim/pages/wallet/withdraw_coin_picker_screen.dart';
import 'package:openim/pages/wallet/withdraw_transfer_target_validator.dart';

import 'wallet_home_test_support.dart';

void main() {
  test('existing coin picker defaults to friend transfers', () {
    expect(const WithdrawCoinPickerScreen().initialTargetKind,
        WithdrawTransferTargetKind.friend);
  });

  final destinations = <String, Type>{
    'receive': WalletDepositCoinPickerScreen,
    'transfer': WithdrawCoinPickerScreen,
    'swap': WalletExchangeScreen,
    'record': WalletRecordScreen,
  };

  for (final entry in destinations.entries) {
    testWidgets('${entry.key} opens the existing wallet route', (tester) async {
      final controller = await loadedHomeController();
      final observer = HomeRouteObserver();
      await pumpWalletHome(tester, controller: controller, observer: observer);
      await tester.pumpAndSettle();
      if (entry.key == 'record') {
        expect(tester.widget(walletHomeKey('wallet-action-record')),
            isA<IconButton>());
      }
      await tester.tap(walletHomeKey('wallet-action-${entry.key}'));
      if (entry.key == 'transfer') {
        expect(observer.lastPush, isA<PopupRoute>());
        await tester.pumpAndSettle();
        expect(walletHomeKey('wallet-withdraw-type-sheet'), findsOneWidget);
        await tester.tap(walletHomeKey('wallet-withdraw-type-chain'));
      }
      final pushed = observer.lastPush;
      expect(pushed, isA<AppMaterialPageRoute<void>>());
      final destination = (pushed! as PageRouteBuilder).pageBuilder(
        tester.element(find.byType(WalletHomeView)),
        const AlwaysStoppedAnimation(1),
        const AlwaysStoppedAnimation(0),
      );
      expect(destination.runtimeType, entry.value);
      if (destination is WalletRecordScreen) {
        expect(destination.initialCoin, isNull);
      }
      if (destination is WithdrawCoinPickerScreen) {
        expect(destination.initialTargetKind, WithdrawTransferTargetKind.chain,
            reason:
                'The wallet withdrawal action starts with a chain address.');
      }
      // Check the actual route target before mounting secondary pages. Their
      // backend configuration belongs to their own tests, not home layout.
      observer.navigator!.removeRoute(pushed);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('internal transfer selection opens the friend coin picker',
      (tester) async {
    final controller = await loadedHomeController();
    final observer = HomeRouteObserver();
    await pumpWalletHome(tester, controller: controller, observer: observer);
    await tester.pumpAndSettle();
    await tester.tap(walletHomeKey('wallet-action-transfer'));
    expect(observer.lastPush, isA<PopupRoute>());
    await tester.pumpAndSettle();
    await tester.tap(walletHomeKey('wallet-withdraw-type-friend'));
    final pushed = observer.lastPush;
    expect(pushed, isA<AppMaterialPageRoute<void>>());
    final destination = (pushed! as PageRouteBuilder).pageBuilder(
      tester.element(find.byType(WalletHomeView)),
      const AlwaysStoppedAnimation(1),
      const AlwaysStoppedAnimation(0),
    );
    expect(destination, isA<WithdrawCoinPickerScreen>());
    expect((destination as WithdrawCoinPickerScreen).initialTargetKind,
        WithdrawTransferTargetKind.friend);
    observer.navigator!.removeRoute(pushed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('dismissing the withdrawal sheet leaves the wallet home open',
      (tester) async {
    final controller = await loadedHomeController();
    final observer = HomeRouteObserver();
    await pumpWalletHome(tester, controller: controller, observer: observer);
    await tester.pumpAndSettle();
    await tester.tap(walletHomeKey('wallet-action-transfer'));
    final sheetRoute = observer.lastPush;
    expect(sheetRoute, isA<PopupRoute>());
    await tester.pumpAndSettle();
    observer.navigator!.pop();
    await tester.pumpAndSettle();
    expect(walletHomeKey('wallet-withdraw-type-sheet'), findsNothing);
    expect(observer.lastPush, same(sheetRoute),
        reason: 'Canceling must not push a coin picker.');
    expect(find.byType(WalletHomeView), findsOneWidget);
    expect(find.byType(WithdrawCoinPickerScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated withdrawal taps open one sheet and permit reopening',
      (tester) async {
    final controller = await loadedHomeController();
    final observer = HomeRouteObserver();
    await pumpWalletHome(tester, controller: controller, observer: observer);
    await tester.pumpAndSettle();
    final action = tester
        .widget<WalletHomeAction>(walletHomeKey('wallet-action-transfer'));
    action.onTap();
    final firstSheet = observer.lastPush;
    action.onTap();
    expect(observer.lastPush, same(firstSheet));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('wallet-withdraw-type-sheet'),
            skipOffstage: false),
        findsOneWidget);
    observer.navigator!.pop();
    await tester.pumpAndSettle();
    expect(walletHomeKey('wallet-withdraw-type-sheet'), findsNothing);
    action.onTap();
    expect(observer.lastPush, isA<PopupRoute>());
    expect(observer.lastPush, isNot(same(firstSheet)));
    await tester.pumpAndSettle();
    expect(walletHomeKey('wallet-withdraw-type-sheet'), findsOneWidget);
    observer.navigator!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(WithdrawCoinPickerScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asset overview icon toggles the inline trend without a route',
      (tester) async {
    final controller = await loadedHomeController();
    final observer = HomeRouteObserver();
    await pumpWalletHome(tester,
        controller: controller, observer: observer, size: const Size(390, 320));
    await tester.pumpAndSettle();
    final icon =
        tester.widget<IconButton>(walletHomeKey('wallet-action-overview'));
    expect(icon.tooltip, '展开资产趋势');
    expect(icon.isSelected, isFalse);
    final assetsTop =
        tester.getRect(walletHomeKey('wallet-assets-section')).top;
    await tester.tap(walletHomeKey('wallet-action-overview'));
    await tester.pumpAndSettle();
    expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
    expect(tester.getRect(walletHomeKey('wallet-assets-section')).top,
        greaterThan(assetsTop));
    expect(observer.lastPush, isNull);
    await tester.tap(walletHomeKey('wallet-action-overview'));
    await tester.pumpAndSettle();
    expect(walletHomeKey('wallet-trend-panel'), findsNothing);
    expect(tester.getRect(walletHomeKey('wallet-assets-section')).top,
        closeTo(assetsTop, .01));
    expect(observer.lastPush, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final code in ['99', 'USDT']) {
    testWidgets('asset $code opens transaction history with its coin filter',
        (tester) async {
      final controller = await loadedHomeController();
      final observer = HomeRouteObserver();
      await pumpWalletHome(tester, controller: controller, observer: observer);
      await tester.pumpAndSettle();
      await tester.ensureVisible(walletHomeKey('wallet-asset-$code'));
      await tester.tap(walletHomeKey('wallet-asset-$code'));
      final pushed = observer.lastPush! as PageRouteBuilder;
      final destination = pushed.pageBuilder(
        tester.element(find.byType(WalletHomeView)),
        const AlwaysStoppedAnimation(1),
        const AlwaysStoppedAnimation(0),
      );
      expect(destination, isA<WalletRecordScreen>());
      expect((destination as WalletRecordScreen).initialCoin, code);
      observer.navigator!.removeRoute(pushed);
      await tester.pumpAndSettle();
      expect(controller.showBal, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
