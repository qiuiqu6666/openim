import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/host/wallet_navigation.dart';
import 'package:openim/pages/wallet/host/wallet_qr_scanner.dart';
import 'package:openim/pages/wallet/withdrawal/form/wallet_chain_withdrawal_screen.dart';
import 'package:openim/widgets/qr_scanner/qr_gallery_service.dart';
import 'package:qr_code_scanner_plus/qr_code_scanner_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../support/contacts/native_qr_scanner.dart';
import '../operations/support/wallet_operation_test_support.dart';
import 'support/wallet_scanner_fixture.dart';

const _recipient = 'TP4TT7nd1UEf52K2VXL3678qGbPMYnKaqj';

class _PngGallery extends QrGalleryService {
  _PngGallery(this.path);
  final String path;
  Future<String?>? decoding;
  @override
  Future<String?> pickImage() async => path;
  @override
  Future<String?> readCode(String path) => decoding = super.readCode(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeWalletScannerTests);

  for (final fromActualPng in [false, true]) {
    testWidgets(
        'real scanner ${fromActualPng ? 'PNG decode' : 'native camera'} fills withdrawal address without a transaction',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final native = NativeQrScanner(tester);
      Directory? temp;
      try {
        QrGalleryService gallery = WalletScannerGallery();
        if (fromActualPng) {
          await tester.runAsync(() async {
            temp = await Directory.systemTemp.createTemp('wallet_scanner_png_');
            final file = File('${temp!.path}/recipient.png');
            await file.writeAsBytes(image.encodePng(_qrPixels(_recipient)));
            gallery = _PngGallery(file.path);
          });
        }
        final api = WalletOperationTestApi();
        final operation = testWalletOperation(WalletOperationKind.withdraw, api,
            accountID: 'wallet-scanner-integration');
        await pumpWalletOperation(
            tester,
            WalletChainWithdrawalScreen(
              coin: withdrawalTestCoin(FundCurrency.usdt),
              payMethod: withdrawalTestMethod(FundCurrency.usdt),
              api: api,
              coordinator: operation,
              accountProvider: () => operation.accountKey,
              scanAddress: (context) => openWalletPage<String>(
                  context,
                  MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(disableAnimations: true),
                    child: WalletQrScannerPage(
                        gallery: gallery, onMyQrTap: () async {}),
                  )),
            ));
        final scan = find.byKey(const ValueKey('wallet-chain-scan'));
        await tester.ensureVisible(scan);
        await tester.tap(scan);
        await tester.pumpAndSettle();
        expect(find.byType(QRView), findsOneWidget);
        await native.permission(true);
        await tester.pumpAndSettle();
        if (fromActualPng) {
          await tester.runAsync(() async {
            // Start the real isolate decoder in a real async zone, rather than
            // awaiting an isolate future created inside Flutter's fake clock.
            await tester.tap(walletScannerAction('album'));
            await tester.pump();
            expect(
                await (gallery as _PngGallery)
                    .decoding!
                    .timeout(const Duration(seconds: 5)),
                _recipient);
          });
        } else {
          await native.recognize(' \n$_recipient  ');
        }
        await tester.pumpAndSettle();
        expect(find.byType(QRView), findsNothing);
        final address = tester.widget<TextField>(find.descendant(
            of: find.byKey(const ValueKey('wallet-chain-address')),
            matching: find.byType(TextField)));
        expect(address.controller!.text, _recipient);
        expect(address.controller!.selection.baseOffset, _recipient.length);
        expect(operation.draft, isNull);
        expect(api.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        native.dispose();
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        if (temp != null) {
          await tester.runAsync(() => temp!.delete(recursive: true));
        }
      }
    });
  }
}

image.Image _qrPixels(String text) {
  final qr = QrImage(
      QrCode.fromData(data: text, errorCorrectLevel: QrErrorCorrectLevel.M));
  const scale = 6;
  const quiet = 4;
  final side = (qr.moduleCount + quiet * 2) * scale;
  final output = image.Image(width: side, height: side, numChannels: 4);
  image.fill(output, color: image.ColorRgba8(255, 255, 255, 255));
  for (var y = 0; y < qr.moduleCount; y++) {
    for (var x = 0; x < qr.moduleCount; x++) {
      if (!qr.isDark(y, x)) continue;
      image.fillRect(output,
          x1: (x + quiet) * scale,
          y1: (y + quiet) * scale,
          x2: (x + quiet + 1) * scale - 1,
          y2: (y + quiet + 1) * scale - 1,
          color: image.ColorRgba8(0, 0, 0, 255));
    }
  }
  return output;
}
