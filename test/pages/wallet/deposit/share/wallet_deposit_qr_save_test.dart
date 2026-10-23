import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/deposit/share/wallet_deposit_share_tokens.dart';
import 'package:openim/pages/wallet/deposit/wallet_deposit_tokens.dart';
import 'package:openim/pages/wallet/wallet_share_service.dart';

import '../support/wallet_deposit_qr_expectation.dart';
import '../support/wallet_deposit_test_support.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final brightness in Brightness.values) {
    testWidgets('tap saves only a scannable QR in $brightness', (tester) async {
      final share = DepositTestShareService();
      await pumpWalletDeposit(tester,
          api: WalletTestFundApi(), share: share, brightness: brightness);
      await tester.tap(depositKey('wallet-deposit-share'));
      await tester.pumpAndSettle();
      await tester.tap(depositKey('wallet-deposit-save-qr'));
      await tester.pumpAndSettle();
      expect(share.saves, hasLength(1));
      expect(share.saveBackgrounds.single, WalletDepositTokens.qrBackground);
      final key = share.saves.single;
      final render =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      expect(render.size, const Size.square(WalletDepositShareTokens.qrSize));
      expect(find.descendant(of: find.byKey(key), matching: find.byType(Text)),
          findsNothing);
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 3);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(
              decodeDepositPngQr(
                  data!.buffer.asUint8List(), Offset.zero & render.size,
                  pixelRatio: 3),
              testDepositAddress);
        } finally {
          image.dispose();
        }
      });
      await tester.tap(depositKey('wallet-deposit-save'));
      await tester.pumpAndSettle();
      expect(share.saves, hasLength(2));
      expect(share.saves.last, isNot(key));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  }

  testWidgets('tap cannot start duplicate saves while saving', (tester) async {
    final pending = Completer<WalletSaveImgResult>();
    final share = DepositTestShareService()
      ..saveResponse = (_, __) => pending.future;
    await pumpWalletDeposit(tester, api: WalletTestFundApi(), share: share);
    await tester.tap(depositKey('wallet-deposit-share'));
    await tester.pumpAndSettle();
    await tester.tap(depositKey('wallet-deposit-save-qr'));
    await tester.pump();
    await tester.tap(depositKey('wallet-deposit-save-qr'));
    expect(share.saves, hasLength(1));
    pending.complete(WalletSaveImgResult.success);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });
}
