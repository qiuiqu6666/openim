import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wallet_deposit_test_support.dart';

void main() {
  testWidgets(
      'card hides contract information and its address still copies directly',
      (tester) async {
    final service = DepositTestShareService();
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    expect(find.text(testUsdtContract), findsNothing);
    expect(find.text('合约信息'), findsNothing);
    expect(find.text('USDT 合约信息'), findsNothing);
    for (final key in [
      'wallet-deposit-contract-info',
      'wallet-deposit-contract-preview',
      'wallet-deposit-contract-dialog',
      'wallet-deposit-contract',
      'wallet-deposit-info-copy',
    ]) {
      expect(depositKey(key), findsNothing);
    }
    expect(depositKey('wallet-deposit-address-info'), findsNothing);
    expect(depositKey('wallet-deposit-copy'), findsNothing);
    expect(tester.widget<Text>(depositKey('wallet-deposit-address')).data,
        testDepositAddress);
    await EasyLoading.dismiss(animation: false);
    await tester.tap(depositKey('wallet-deposit-address'));
    await _settleToast(tester);
    expect(service.copies, [testDepositAddress]);
    expect(depositKey('wallet-deposit-address-dialog'), findsNothing);
    expect(tester.takeException(), isNull);
    await EasyLoading.dismiss(animation: false);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'address title, text and whitespace each copy once with centered feedback',
      (tester) async {
    final service = DepositTestShareService();
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    final area = depositKey('wallet-deposit-address-copy');
    final pageCenter = tester.getCenter(find.byType(Scaffold));
    final title = find.descendant(of: area, matching: find.text('USDT充值地址'));
    final whitespace = tester.getRect(area).bottomRight - const Offset(4, 4);
    var shown = 0;
    void onStatus(EasyLoadingStatus status) {
      if (status == EasyLoadingStatus.show) shown++;
    }

    EasyLoading.addStatusCallback(onStatus);
    addTearDown(() => EasyLoading.removeCallback(onStatus));
    for (var target = 0; target < 3; target++) {
      if (target == 0) {
        await tester.tap(title);
      } else if (target == 1) {
        await tester.tap(depositKey('wallet-deposit-address'));
      } else {
        await tester.tapAt(whitespace);
      }
      await _settleToast(tester);
      expect(service.copies, List.filled(target + 1, testDepositAddress));
      expect(shown, target + 1);
      expect(find.text('地址已复制'), findsOneWidget);
      final toastCenter = tester.getCenter(find.text('地址已复制'));
      expect(toastCenter.dx, closeTo(pageCenter.dx, 1));
      expect(toastCenter.dy, closeTo(pageCenter.dy, 1));
      await EasyLoading.dismiss(animation: false);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('network information offers only the authenticated TRON network',
      (tester) async {
    await pumpWalletDeposit(tester, api: WalletTestFundApi());
    await tester.tap(depositKey('wallet-deposit-network-info'));
    await tester.pumpAndSettle();
    expect(depositKey('wallet-deposit-help-sheet'), findsOneWidget);
    expect(
        find.descendant(
            of: depositKey('wallet-deposit-help-sheet'),
            matching: find.textContaining('TRON')),
        findsOneWidget);
    expect(find.textContaining('Ethereum'), findsNothing);
    expect(find.textContaining('BSC'), findsNothing);
    expect(find.textContaining('无须'), findsNothing);
    expect(
        find.descendant(
            of: depositKey('wallet-deposit-help-sheet'),
            matching: find.textContaining('无需')),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a stale account cannot copy through the previous card callback',
      (tester) async {
    var account = 'server:first-user';
    final service = DepositTestShareService();
    await pumpWalletDeposit(tester,
        api: WalletTestFundApi(),
        accountProvider: () => account,
        share: service);
    final copyAddress = tester
        .widget<InkWell>(depositKey('wallet-deposit-address-copy'))
        .onTap!;
    account = 'server:second-user';
    // The prior card's callback must be safe even after the owner changed.
    copyAddress();
    await tester.pump();
    expect(service.copies, isEmpty);
    expect(EasyLoading.isShow, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'failed allocation exposes retry rather than usable address or raw errors',
      (tester) async {
    final api = WalletTestFundApi()
      ..respondAddress = () =>
          Future.error(const FormatException('Invalid wallet address data'));
    await pumpWalletDeposit(tester, api: api);
    expect(depositKey('wallet-deposit-error'), findsOneWidget);
    expect(depositKey('wallet-deposit-retry'), findsOneWidget);
    for (final key in [
      'wallet-deposit-qr',
      'wallet-deposit-copy',
      'wallet-deposit-address-copy',
      'wallet-deposit-share'
    ]) {
      expect(depositKey(key), findsNothing);
    }
    expect(find.textContaining('Invalid wallet'), findsNothing);
    api.respondAddress = null;
    await tester.tap(depositKey('wallet-deposit-retry'));
    await tester.pumpAndSettle();
    expect(api.addressCalls, 2);
    expect(depositKey('wallet-deposit-qr'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<void> _settleToast(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}
