import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/exchange/data/wallet_swap_quote_controller.dart';
import 'package:openim/pages/wallet/wallet_exchange_screen.dart';
import 'package:openim/pages/wallet/withdraw_chain_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/wallet_operation_test_support.dart';

// Optional real-widget screenshots. All balances, fees and orders are fixtures.
const _directory = String.fromEnvironment('WALLET_OPERATIONS_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (_directory.isEmpty) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      await (FontLoader('WalletOperationPreviewCjk')
            ..addFont(Future.value(bytes)))
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
    for (final pageKind in [
      'swap',
      'swap-input',
      'swap-long',
      'swap-completed',
      'swap-payment-success',
      'swap-quote',
      'swap-quote-expired',
      'withdraw-usdt',
      'withdraw-trx'
    ]) {
      testWidgets('actual $pageKind ${brightness.name} preview',
          skip: _directory.isEmpty, (tester) async {
        final api = WalletOperationTestApi();
        var now = DateTime.now();
        api.now = () => now;
        final key = GlobalKey();
        final Widget page;
        if (pageKind.startsWith('swap')) {
          page = WalletExchangeScreen(
              coordinator: testWalletOperation(WalletOperationKind.swap, api),
              settingsService: WalletOperationTestSettings(),
              quoteController: WalletSwapQuoteController(
                  api: api, isActive: () => true, now: () => now));
        } else {
          final currency =
              pageKind == 'withdraw-trx' ? FundCurrency.trx : FundCurrency.usdt;
          page = WithdrawChainReviewScreen(
              coin: withdrawalTestCoin(currency),
              payMethod: withdrawalTestMethod(currency),
              toAddress: walletOperationTestAddress,
              amountMinor: 1123456,
              coordinator:
                  testWalletOperation(WalletOperationKind.withdraw, api));
        }
        await pumpWalletOperation(tester, page,
            brightness: brightness,
            boundaryKey: key,
            fontFamily: 'WalletOperationPreviewCjk');
        if (pageKind == 'swap-input') {
          await enterWalletSwapAmount(tester, '12.345678');
        } else if (pageKind == 'swap-long') {
          await enterWalletSwapAmount(tester, '1234567890123456789.123456');
        } else if (pageKind == 'swap-completed') {
          await enterWalletSwapAmount(tester, '12.345678');
          await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
          await tester.pumpAndSettle();
          await confirmWalletSwapQuote(tester);
          await enterWalletOperationPin(tester);
        } else if (pageKind == 'swap-payment-success') {
          await enterWalletSwapAmount(tester, '12.345678');
          await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
          await tester.pumpAndSettle();
          await confirmWalletSwapQuote(tester);
          for (final digit in '123456'.split('')) {
            await tester.tap(find.text(digit).last);
            await tester.pump();
          }
          await tester.pumpAndSettle();
          expect(find.text('支付成功'), findsOneWidget);
        } else if (pageKind.startsWith('swap-quote')) {
          await enterWalletSwapAmount(tester, '12.345678');
          await tester.tap(find.byKey(const ValueKey('wallet-swap-submit')));
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('wallet-swap-quote-confirm')),
              findsOneWidget);
          if (pageKind == 'swap-quote-expired') {
            now = now.add(const Duration(seconds: 31));
            await tester.pump(const Duration(seconds: 31));
            await tester.pumpAndSettle();
            expect(find.byKey(const ValueKey('wallet-swap-quote-expired')),
                findsOneWidget);
            expect(
                tester
                    .widget<FilledButton>(
                        find.byKey(const ValueKey('wallet-swap-quote-confirm')))
                    .onPressed,
                isNull);
          }
        }
        // Asset decoding completes outside the test clock. Wait for every
        // actual Image provider before exporting the rendered page.
        await tester.runAsync(() async {
          final images = find.byType(Image).evaluate().toList();
          for (final element in images) {
            await precacheImage((element.widget as Image).image, element);
          }
          for (final element in find.byType(SvgPicture).evaluate().toList()) {
            final picture = await vg.loadPicture(
                (element.widget as SvgPicture).bytesLoader, element);
            picture.picture.dispose();
          }
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
            api.writes,
            hasLength(pageKind == 'swap-completed' ||
                    pageKind == 'swap-payment-success'
                ? 1
                : 0));
        final boundary =
            key.currentContext!.findRenderObject() as RenderRepaintBoundary;
        // Paint the actual completed vector/image frame before raster capture.
        boundary.markNeedsPaint();
        await tester.pump();
        await tester.runAsync(() async {
          final output = Directory(_directory)..createSync(recursive: true);
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${output.path}/wallet-$pageKind-${brightness.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          await File('${output.path}/wallet-operation-preview-notes.txt')
              .writeAsString(
                  '真实 Flutter 提现/闪兑 Widget；余额和金额仅用于测试，未访问真实账户或发送资金请求。\n'
                  '闪兑报价、美元估值和预计实得数量来自独立测试 fixture；输入原始数量保留完整精度，金额展示为两位小数。\n'
                  '空输入/超出支持范围时不提供报价；提现手续费尚未取得响应时显示 --。\n');
          image.dispose();
        });
        if (pageKind == 'swap-payment-success') {
          await tester.pump(const Duration(milliseconds: 900));
          await tester.pumpAndSettle();
          await tester.pump(const Duration(seconds: 3));
          await tester.pumpAndSettle();
        }
        await disposeWalletOperationPage(tester);
      });
    }
  }
}
