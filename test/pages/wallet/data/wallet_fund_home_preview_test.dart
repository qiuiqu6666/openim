import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';

import '../home/wallet_home_test_support.dart';
import 'wallet_fund_test_api.dart';

const _directory = String.fromEnvironment('WALLET_DEPOSIT_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory.isEmpty) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await (FontLoader('WalletFundHomePreviewCjk')
            ..addFont(
                Future.value(ByteData.sublistView(await font.readAsBytes()))))
          .load();
    }
    final icons = File(
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes()))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('fund adapter uses the existing home in ${brightness.name}',
        skip: _directory.isEmpty, (tester) async {
      final repository = WalletFundRepository(
          api: WalletTestFundApi(), accountProvider: () => 'preview:user');
      final controller = WalletController(repo: repository);
      addTearDown(controller.dispose);
      await controller.load();
      final boundaryKey = GlobalKey();
      await pumpWalletHome(tester,
          controller: controller,
          brightness: brightness,
          boundaryKey: boundaryKey,
          fontFamily: 'WalletFundHomePreviewCjk');
      await settleWalletHomeImages(tester);
      expect(walletHomeKey('wallet-asset-99'), findsOneWidget);
      expect(walletHomeKey('wallet-asset-USDT'), findsOneWidget);
      expect(walletHomeKey('wallet-asset-TRX'), findsOneWidget);
      expect(find.text('12.35'), findsOneWidget);
      expect(find.text('8.01'), findsOneWidget);
      expect(find.text('9.00'), findsOneWidget);
      expect(find.textContaining('暂时无法获取资产'), findsNothing);
      expect(tester.takeException(), isNull);
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = Directory(_directory)..createSync(recursive: true);
          await File(
                  '${directory.path}/wallet-fund-home-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
    });
  }
}
