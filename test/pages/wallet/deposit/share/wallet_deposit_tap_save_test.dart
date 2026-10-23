import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim/pages/wallet/wallet_share_service.dart';

import '../support/wallet_deposit_test_support.dart';

void main() {
  testWidgets(
      'QR tap retries failure, blocks rapid taps and remembers saved QR on return',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pending = Completer<WalletSaveImgResult>();
    final share = DepositTestShareService()
      ..saveResponse = (_, __) => pending.future;
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: share);
    final qr = depositKey('wallet-deposit-tap-save-qr');
    await tester.tap(qr);
    await tester.pump();
    await tester.tap(qr);
    await tester.pump();
    expect(share.saves, hasLength(1));
    final boundary = share.saves.single;
    expect(boundary.currentContext!.findRenderObject(),
        isA<RenderRepaintBoundary>());
    expect(
        find.descendant(of: find.byKey(boundary), matching: find.byType(Text)),
        findsNothing);
    pending.complete(WalletSaveImgResult.permissionDenied);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    share.saveResponse = null;
    await tester.tap(qr);
    await tester.pumpAndSettle();
    expect(share.saves, hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(qr);
    await tester.pumpAndSettle();
    expect(share.saves, hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox());
    await pumpWalletDeposit(tester,
        api: WalletTestFundApi(), share: share, brightness: Brightness.dark);
    await tester.tap(qr);
    await tester.pumpAndSettle();
    expect(share.saves, hasLength(2));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
