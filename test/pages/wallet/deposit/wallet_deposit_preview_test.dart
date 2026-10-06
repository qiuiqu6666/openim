import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_repository.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/deposit/widgets/wallet_deposit_share_preview.dart';

import '../record/support/wallet_record_test_support.dart';
import 'support/wallet_deposit_qr_expectation.dart';
import 'support/wallet_deposit_test_support.dart';

// Actual production widgets, with all addresses/events injected from test fixtures.
const _directory = String.fromEnvironment('WALLET_DEPOSIT_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory.isEmpty) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await (FontLoader('WalletDepositPreviewCjk')
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
    testWidgets('export complete share preview ${brightness.name}',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      await pumpWalletDeposit(tester,
          api: WalletTestFundApi(),
          boundaryKey: boundary,
          brightness: brightness,
          fontFamily: 'WalletDepositPreviewCjk');
      await _settleDeposit(tester);
      await tester.ensureVisible(depositKey('wallet-deposit-share'));
      await tester.tap(depositKey('wallet-deposit-share'));
      await tester.pumpAndSettle();
      expect(find.byType(WalletDepositSharePreview), findsOneWidget);
      final shareBoundary = find
          .ancestor(
              of: find.byType(WalletDepositSharePreview),
              matching: find.byType(RepaintBoundary))
          .first;
      final repaint = tester.renderObject<RenderRepaintBoundary>(shareBoundary);
      expect(tester.takeException(), isNull);
      await _exportRender(tester, repaint,
          'wallet-deposit-share-preview-${brightness.name}.png',
          qr: find.descendant(
              of: find.byType(WalletDepositSharePreview),
              matching: depositKey('wallet-deposit-qr')));
      await tester.pumpWidget(const SizedBox.shrink());
    });
    for (final ready in [false, true]) {
      testWidgets(
          'export deposit ${ready ? "ready" : "pending"} ${brightness.name}',
          skip: _directory.isEmpty, (tester) async {
        final boundary = GlobalKey();
        final api =
            WalletTestFundApi(address: depositAddressFixture(ready: ready));
        await pumpWalletDeposit(tester,
            api: api,
            boundaryKey: boundary,
            brightness: brightness,
            fontFamily: 'WalletDepositPreviewCjk');
        await _settleDeposit(tester);
        expect(
            depositKey(ready ? 'wallet-deposit-qr' : 'wallet-deposit-pending'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await _export(tester, boundary,
            'wallet-deposit-${ready ? "ready" : "pending"}-${brightness.name}.png',
            qr: ready ? depositKey('wallet-deposit-qr') : null);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    for (final variant in ['trx', 'large-text']) {
      testWidgets('export ready $variant ${brightness.name}',
          skip: _directory.isEmpty, (tester) async {
        final boundary = GlobalKey();
        final large = variant == 'large-text';
        await pumpWalletDeposit(tester,
            api: WalletTestFundApi(),
            boundaryKey: boundary,
            brightness: brightness,
            currency: large ? FundCurrency.usdt : FundCurrency.trx,
            size: Size(large ? 320 : 390, 844),
            textScale: large ? 2 : 1,
            fontFamily: 'WalletDepositPreviewCjk');
        await _settleDeposit(tester);
        expect(depositKey('wallet-deposit-qr'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _export(tester, boundary,
            'wallet-deposit-ready-$variant-${brightness.name}.png',
            qr: depositKey('wallet-deposit-qr'));
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
    testWidgets('export fund events with unknown timestamps ${brightness.name}',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      await pumpWalletRecords(tester,
          repository: WalletFundRepository(
              api: WalletTestFundApi(), accountProvider: () => 'preview:user'),
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletDepositPreviewCjk');
      await settleWalletRecordImages(tester);
      expect(walletRecordKey('wallet-record-month-unknown'), findsOneWidget);
      expect(walletRecordKey('wallet-record-source-notice'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _export(
          tester, boundary, 'wallet-deposit-records-${brightness.name}.png');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}

Future<void> _settleDeposit(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(depositKey('wallet-deposit-records'));
    for (final asset in const [
      'lib/pages/wallet/widgets/assets/trx.png',
      'lib/pages/wallet/widgets/assets/usdt.webp',
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pumpAndSettle();
}

Future<void> _export(WidgetTester tester, GlobalKey boundary, String name,
    {Finder? qr}) async {
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await _exportRender(tester, render, name, qr: qr);
}

Future<void> _exportRender(
    WidgetTester tester, RenderRepaintBoundary render, String name,
    {Finder? qr}) async {
  final rect = qr == null
      ? null
      : tester.getRect(qr).shift(-render.localToGlobal(Offset.zero));
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (rect != null) {
        expect(decodeDepositPngQr(bytes!.buffer.asUint8List(), rect),
            testDepositAddress,
            reason:
                'The exact exported PNG must retain a scannable address QR: $name');
      }
      final output = Directory(_directory)..createSync(recursive: true);
      await File('${output.path}/$name')
          .writeAsBytes(bytes!.buffer.asUint8List());
      await File('${output.path}/preview-notes.txt').writeAsString(
          '真实 Flutter 充值与记录页面；地址、合约、余额和充值事件均为注入的测试夹具，非真实账户。\n'
          '充值 pending 不展示可用地址；ready 的 QR 与文本一致。网络 TRON，仅 USDT/TRX，99 不支持链上充值。\n'
          '记录保留同一交易多个事件，时间/历史余额未知，撤销事件显示失败状态。\n'
          '最低充值量、预计时间、目标账户与提币解锁确认数未提供，不使用截图示例数值。\n'
          '390×844；大字预览 320×844、2 倍文字，亮/暗主题，Microsoft YaHei。\n');
    } finally {
      image.dispose();
    }
  });
}
