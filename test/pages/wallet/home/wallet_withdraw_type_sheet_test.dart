import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/home/widgets/wallet_withdraw_type_sheet.dart';
import 'package:openim/pages/wallet/withdraw_transfer_target_validator.dart';
import 'package:openim/pages/wallet/widgets/wallet_page_colors.dart';

import 'wallet_home_test_support.dart';

const _previewDir = String.fromEnvironment('WALLET_WITHDRAW_PREVIEW_DIR');

void main() {
  setUpAll(() async {
    if (_previewDir.isEmpty) return;
    for (final font in [
      (name: 'WalletPreviewCjk', path: 'C:/Windows/Fonts/msyh.ttc'),
      (
        name: 'MaterialIcons',
        path:
            'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
      ),
    ]) {
      final bytes = await File(font.path).readAsBytes();
      await (FontLoader(font.name)
            ..addFont(Future.value(ByteData.sublistView(bytes))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final layout in const [
      (size: Size(375, 812), scale: 1.0),
      (size: Size(320, 640), scale: 2.0),
      (size: Size(812, 375), scale: 2.0),
    ]) {
      testWidgets(
          'withdrawal choices fit ${layout.size} at ${layout.scale}x in $brightness',
          (tester) async {
        final controller = await loadedHomeController();
        WithdrawTransferTargetKind? selected;
        await pumpWalletHome(tester,
            controller: controller,
            size: layout.size,
            brightness: brightness,
            textScale: layout.scale,
            safePadding: const EdgeInsets.only(top: 24, bottom: 34),
            page: Scaffold(
                body: Builder(
                    builder: (context) => TextButton(
                        onPressed: () async => selected =
                            await showWalletWithdrawTypeSheet(context),
                        child: const Text('打开')))));
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        expect(walletHomeKey('wallet-withdraw-type-sheet'), findsOneWidget);
        expect(find.text('选择提现类型'), findsOneWidget);
        expect(find.text('0手续费'), findsOneWidget);
        final p2p = walletHomeKey('wallet-withdraw-type-p2p');
        expect(
            tester
                .widget<InkWell>(
                    find.descendant(of: p2p, matching: find.byType(InkWell)))
                .onTap,
            isNull);
        final friend = walletHomeKey('wallet-withdraw-type-friend');
        await tester.ensureVisible(friend);
        await tester.pumpAndSettle();
        final rect = tester.getRect(friend);
        expect(rect.width, lessThanOrEqualTo(layout.size.width));
        expect(rect.height, greaterThanOrEqualTo(48));
        expect(rect.bottom, lessThanOrEqualTo(layout.size.height - 34));
        await tester.tap(friend);
        await tester.pumpAndSettle();
        expect(selected, WithdrawTransferTargetKind.friend);
        expect(walletHomeKey('wallet-withdraw-type-sheet'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('export withdrawal selection ${brightness.name}',
        skip: _previewDir.isEmpty, (tester) async {
      final controller = await loadedHomeController();
      final boundary = GlobalKey();
      await pumpWalletHome(tester,
          controller: controller,
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletPreviewCjk',
          page: Scaffold(
              body: Align(
                  alignment: Alignment.bottomCenter,
                  child: Builder(
                      builder: (context) => Material(
                          color: WalletPageColors.of(context).card,
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(20)),
                          child: const WalletWithdrawTypeSheet())))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(_previewDir).create(recursive: true);
        await File('$_previewDir/withdraw-type-${brightness.name}.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    });
  }
}
