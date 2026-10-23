import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/wallet_deposit_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'sheet QR shares save receipt, copy works and only backdrop dismisses',
      (tester) async {
    final service = DepositTestShareService();
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: service);
    await tester.tap(depositKey('wallet-deposit-tap-save-qr'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(service.saves, hasLength(1));
    await tester.tap(depositKey('wallet-deposit-share'));
    await tester.pumpAndSettle();
    await tester.tap(depositKey('wallet-deposit-save-qr'));
    await tester.pumpAndSettle();
    expect(service.saves, hasLength(1));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(depositKey('wallet-deposit-share-copy'));
    await tester.pumpAndSettle();
    expect(service.copies, [testDepositAddress]);
    expect(depositKey('wallet-deposit-share-sheet'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(depositKey('wallet-deposit-share-created-at'));
    await tester.pumpAndSettle();
    expect(depositKey('wallet-deposit-share-sheet'), findsOneWidget);
    final y = tester.getCenter(depositKey('wallet-deposit-save-qr')).dy;
    await tester.tapAt(Offset(4, y));
    await tester.pumpAndSettle();
    expect(depositKey('wallet-deposit-share-sheet'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'full single-line address and copy control fit 320px at 2x in $brightness',
        (tester) async {
      final service = DepositTestShareService();
      await pumpWalletDeposit(tester,
          api: WalletTestFundApi(),
          share: service,
          brightness: brightness,
          size: const Size(320, 700),
          textScale: 2);
      await tester.ensureVisible(depositKey('wallet-deposit-share'));
      await tester.tap(depositKey('wallet-deposit-share'));
      await tester.pumpAndSettle();
      final address = depositKey('wallet-deposit-share-address');
      final text = tester.widget<Text>(address);
      expect(text.data, testDepositAddress);
      expect(text.maxLines, 1);
      expect(text.softWrap, isFalse);
      expect(find.ancestor(of: address, matching: find.byType(FittedBox)),
          findsOneWidget);
      await tester.ensureVisible(depositKey('wallet-deposit-share-copy'));
      await tester.pumpAndSettle();
      final copyRect = tester.getRect(depositKey('wallet-deposit-share-copy'));
      expect(copyRect.width, greaterThanOrEqualTo(48));
      expect(copyRect.right, lessThanOrEqualTo(320));
      await tester.tap(depositKey('wallet-deposit-share-copy'));
      await tester.pumpAndSettle();
      expect(service.copies, [testDepositAddress]);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  }
}
