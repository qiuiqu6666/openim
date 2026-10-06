import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/withdraw_chain_review_screen.dart';
import 'package:openim/pages/wallet/withdraw_transfer_confirm_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../operations/support/wallet_operation_test_support.dart';

// Optional screenshots of production widgets, using isolated test fixtures.
const _directory = String.fromEnvironment('WALLET_CURRENCY_RULES_PREVIEW_DIR');
const _fontFamily = 'WalletCurrencyRulesPreviewCjk';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    if (_directory.isEmpty) return;
    for (final entry in {
      _fontFamily: 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      expect(file.existsSync(), isTrue,
          reason: 'Preview font must be available: ${entry.value}');
      await (FontLoader(entry.key)
            ..addFont(
                Future.value(ByteData.sublistView(await file.readAsBytes()))))
          .load();
    }
  });

  for (final brightness in Brightness.values) {
    for (final currency in [FundCurrency.usdt, FundCurrency.trx]) {
      for (final kind in ['review', 'amount-entry']) {
        testWidgets('actual $kind ${currency.code} ${brightness.name} rules',
            skip: _directory.isEmpty, (tester) async {
          await _preview(tester,
              kind: kind, currency: currency, brightness: brightness);
        });
      }
    }

    testWidgets('actual amount-entry TRX large ${brightness.name} rules',
        skip: _directory.isEmpty, (tester) async {
      await _preview(tester,
          kind: 'amount-entry',
          currency: FundCurrency.trx,
          brightness: brightness,
          largeText: true);
    });
  }
}

Future<void> _preview(WidgetTester tester,
    {required String kind,
    required FundCurrency currency,
    required Brightness brightness,
    bool largeText = false}) async {
  final api = WalletOperationTestApi();
  final boundary = GlobalKey();
  final review = kind == 'review';
  final Widget page = review
      ? WithdrawChainReviewScreen(
          coin: withdrawalTestCoin(currency),
          payMethod: withdrawalTestMethod(currency),
          toAddress: walletOperationTestAddress,
          amountMinor: 1123456,
          api: api,
          coordinator: testWalletOperation(WalletOperationKind.withdraw, api),
          settingsService: WalletOperationTestSettings(),
        )
      : WithdrawTransferConfirmScreen(
          mode: WithdrawTransferMode.chain,
          coin: withdrawalTestCoin(currency),
          payMethod: withdrawalTestMethod(currency),
          targetValue: walletOperationTestAddress,
          api: api,
          accountProvider: () => 'currency-rules-preview-user',
        );

  await pumpWalletOperation(tester, page,
      brightness: brightness,
      size: Size(largeText ? 320 : 390, 844),
      textScale: largeText ? 2 : 1,
      boundaryKey: boundary,
      fontFamily: _fontFamily);
  if (!review) {
    // Enter through the real, visible keypad rather than a text controller.
    for (final character in '1.123456'.split('')) {
      final key = find.text(character).last;
      await tester.ensureVisible(key);
      await tester.pumpAndSettle();
      await tester.tap(key);
      await tester.pump();
    }
  }

  final prefix = review ? 'wallet-withdraw' : 'wallet-withdraw-entry';
  final totalKey = '$prefix-${review ? 'total-debit' : 'total'}';
  expect(_text(tester, '$prefix-minimum'), '最低提现：0.1 ${currency.code}');
  expect(_text(tester, '$prefix-fee'), '手续费：0.25 ${currency.code}');
  expect(_text(tester, totalKey), '总扣款：1.373456 ${currency.code}');
  expect(api.depositAddressCalls, 1);
  expect(api.writes, isEmpty);
  if (review) {
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('wallet-withdraw-confirm')))
            .onPressed,
        isNotNull);
  } else {
    expect(tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
        isNotNull);
  }
  if (largeText) {
    await tester.ensureVisible(find.byKey(ValueKey(totalKey)));
    await tester.pumpAndSettle();
  }

  // Decode the current bundled coin artwork outside Flutter's test clock.
  await tester.runAsync(() async {
    final context = boundary.currentContext!;
    for (final asset in [
      'lib/pages/wallet/widgets/assets/trx.png',
      'lib/pages/wallet/widgets/assets/usdt.webp',
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
    for (final element in find.byType(Image).evaluate().toList()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);

  final name = 'wallet-withdraw-$kind-${currency.code.toLowerCase()}'
      '${largeText ? '-large' : ''}-${brightness.name}.png';
  await _export(tester, boundary, name);
  await disposeWalletOperationPage(tester);
}

String? _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data;

Future<void> _export(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  render.markNeedsPaint();
  await tester.pump();
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory(_directory)..createSync(recursive: true);
      await File('${output.path}/$name')
          .writeAsBytes(bytes!.buffer.asUint8List());
      await File('${output.path}/preview-notes.txt').writeAsString(
          '真实 Flutter 提现确认页和金额输入页；本金、余额和币种规则均为隔离测试 fixture。\n'
          '未访问真实账户、服务端或提交资金请求。\n'
          'USDT/TRX 最低提现 0.1、同币手续费 0.25；本金 1.123456，总扣款 1.373456。\n'
          '亮/暗主题 390×844；额外 TRX 大字预览为 320×844、2 倍文字。\n'
          'Microsoft YaHei 和 MaterialIcons；PNG 以 2 倍像素比从实际 RenderRepaintBoundary 导出。\n');
    } finally {
      image.dispose();
    }
  });
}
