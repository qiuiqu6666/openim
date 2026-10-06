import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/data/wallet_operation_pending_store.dart';
import 'package:openim/pages/wallet/withdrawal/form/wallet_chain_withdrawal_screen.dart';
import 'package:openim/pages/wallet/widgets/pay_password_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../operations/support/wallet_operation_test_support.dart';

const _recipient = 'TP4TT7nd1UEf52K2VXL3678qGbPMYnKaqj';
const _previewDirectory = '.temp/chain-withdrawal-reference';
final _exportPreviews =
    const bool.fromEnvironment('EXPORT_CHAIN_WITHDRAWAL_PREVIEWS') ||
        Platform.environment['EXPORT_CHAIN_WITHDRAWAL_PREVIEWS']
                ?.toLowerCase() ==
            'true';

/// Preview fixtures only: all reads are local and no payment is initiated.
class _PreviewApi extends WalletOperationTestApi {
  @override
  Future<WalletDepositAddress> fetchDepositAddress() async {
    depositAddressCalls++;
    return WalletDepositAddress(
      status: 'ready',
      network: 'TRON',
      address: walletOperationTestAddress,
      currencies: const [FundCurrency.usdt, FundCurrency.trx],
      confirmations: 19,
      usdtContract: 'fixture-contract',
      currencyRules: {
        FundCurrency.usdt: WalletCurrencyRule(
          currency: FundCurrency.usdt,
          minWithdrawAmount: '0.1',
          withdrawFee: '0.25',
          withdrawFeeCurrency: FundCurrency.usdt,
        ),
      },
    );
  }

  @override
  Future<WalletWithdrawResult> withdraw({
    required String clientOrderID,
    required FundAmount amount,
    required String toAddress,
    required String payPassword,
    String? verifyChallengeID,
    String? verifyCode,
  }) =>
      throw StateError('A layout preview must never submit a withdrawal.');
}

class _PreviewVariant {
  const _PreviewVariant(this.name, this.size,
      {this.brightness = Brightness.light,
      this.textScale = 1,
      this.keyboardInset = 0});

  final String name;
  final Size size;
  final Brightness brightness;
  final double textScale;
  final double keyboardInset;
}

Finder _key(String suffix) => find.byKey(ValueKey('wallet-chain-$suffix'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(_loadPreviewFonts);

  for (final variant in const [
    _PreviewVariant('light', Size(393, 852)),
    _PreviewVariant('dark', Size(393, 852), brightness: Brightness.dark),
    _PreviewVariant('320-large-text', Size(320, 852), textScale: 2),
    _PreviewVariant('keyboard', Size(393, 852), keyboardInset: 360),
    _PreviewVariant('landscape', Size(852, 393)),
  ]) {
    testWidgets('one-page withdrawal layout ${variant.name}', (tester) async {
      final api = _PreviewApi();
      final settings = WalletOperationTestSettings();
      final boundary = GlobalKey();
      await _mount(tester, api, settings, boundary, variant);
      _expectCenteredHeader(tester, variant.size.width);
      await _fillReadyForm(tester);
      _expectCompleteForm(tester);
      expect(tester.takeException(), isNull);

      if (variant.keyboardInset > 0) {
        await tester.enterText(_key('amount'), '12.5');
        tester.view.viewInsets = FakeViewPadding(bottom: variant.keyboardInset);
        await tester.pumpAndSettle();
        await tester.ensureVisible(_key('amount'));
        await tester.pumpAndSettle();
        final keyboardTop = variant.size.height - variant.keyboardInset;
        expect(tester.getRect(_key('amount')).bottom,
            lessThanOrEqualTo(keyboardTop + 1),
            reason: 'The focused amount stays above the simulated keyboard.');
        expect(tester.takeException(), isNull);
        await _exportCurrent(tester, boundary, '${variant.name}-focused');
      }

      await tester.ensureVisible(_key('submit'));
      await tester.pumpAndSettle();
      expect(_key('submit').hitTestable(), findsOneWidget,
          reason: 'The action remains reachable by scrolling at every size.');
      expect(tester.widget<FilledButton>(_key('submit')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      await _exportCurrent(tester, boundary, '${variant.name}-viewport');

      if (variant.keyboardInset == 0) {
        // The exported page may be taller than the phone viewport so that the
        // same production page shows all three fields, summary and action.
        await _exportFullPage(tester, boundary, variant.name);
      } else {
        await _exportCurrent(tester, boundary, '${variant.name}-action');
      }
      _expectNoPayment(api, settings);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }

  testWidgets('network sheet fits a small dark page with large text',
      (tester) async {
    const variant = _PreviewVariant('network-sheet', Size(320, 852),
        brightness: Brightness.dark, textScale: 2);
    final api = _PreviewApi();
    final settings = WalletOperationTestSettings();
    final boundary = GlobalKey();
    await _mount(tester, api, settings, boundary, variant);
    await tester.ensureVisible(_key('network'));
    await tester.tap(_key('network'));
    await tester.pumpAndSettle();

    expect(_key('network-tron'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('TRON'), findsOneWidget);
    expect(find.textContaining('ERC20'), findsNothing);
    expect(find.textContaining('BEP20'), findsNothing);
    _expectNoInformationCard();
    expect(tester.takeException(), isNull);
    await _exportCurrent(tester, boundary, variant.name);

    await tester.ensureVisible(_key('network-tron'));
    await tester.tap(_key('network-tron'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.descendant(of: _key('network'), matching: find.text('TRON')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
    _expectNoPayment(api, settings);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  for (final variant in const [
    _PreviewVariant('light', Size(393, 852)),
    _PreviewVariant('dark', Size(393, 852), brightness: Brightness.dark),
    _PreviewVariant('320-large-text-short', Size(320, 393), textScale: 2),
    _PreviewVariant('landscape-large-text', Size(568, 320),
        brightness: Brightness.dark, textScale: 2),
  ]) {
    testWidgets('compact fee information preserves the draft ${variant.name}',
        (tester) async {
      final api = _PreviewApi();
      final settings = WalletOperationTestSettings();
      final boundary = GlobalKey();
      await _mount(tester, api, settings, boundary, variant);
      await _fillReadyForm(tester);
      _expectCompleteForm(tester);
      final addressBefore = _inputText(tester, 'address');
      final amountBefore = _inputText(tester, 'amount');
      await tester.ensureVisible(_key('fee-info'));
      await tester.pumpAndSettle();
      await tester.tap(_key('fee-info'));
      await tester.pumpAndSettle();

      expect(_key('info-dialog'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.widget<Text>(_key('info-title')).data, '网络手续费');
      expect(
          tester.widget<Text>(_key('info-body')).data, contains('提现数量与手续费之和'));
      expect(
          find.descendant(of: _key('info-close'), matching: find.text('我知道了')),
          findsOneWidget);
      expect(_key('info-close').hitTestable(), findsOneWidget,
          reason:
              'The close action stays visible in short and large-text layouts.');
      expect(
          tester.getSize(_key('info-close')).height, greaterThanOrEqualTo(48));
      final surface = find
          .descendant(of: _key('info-dialog'), matching: find.byType(Material))
          .first;
      final rect = tester.getRect(surface);
      expect(rect.height, lessThanOrEqualTo(variant.size.height * .8 + 1));
      expect(rect.width, lessThanOrEqualTo(variant.size.width - 32 + 1));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.bottom, lessThanOrEqualTo(variant.size.height));
      if (variant.textScale == 1) {
        expect(rect.height, lessThan(variant.size.height * .5),
            reason:
                'Short fee copy uses its content height without a large empty area.');
      }
      expect(tester.takeException(), isNull);
      _expectNoPayment(api, settings);
      await _exportCurrent(tester, boundary, 'fee-dialog-${variant.name}');

      await tester.tap(_key('info-close'));
      await tester.pumpAndSettle();
      expect(_key('info-dialog'), findsNothing);
      expect(_inputText(tester, 'address'), addressBefore);
      expect(_inputText(tester, 'amount'), amountBefore);
      expect(find.descendant(of: _key('network'), matching: find.text('TRON')),
          findsOneWidget);
      _expectCompleteForm(tester);
      expect(tester.widget<FilledButton>(_key('submit')).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
      _expectNoPayment(api, settings);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  }
}

void _expectCenteredHeader(WidgetTester tester, double width) {
  final title = find.text('提现 USDT');
  expect(title, findsOneWidget);
  final titleRect = tester.getRect(title);
  expect(titleRect.center.dx, closeTo(width / 2, .01),
      reason:
          'The title is centered on the page despite two trailing actions.');
  final paragraph = tester.renderObject<RenderParagraph>(
      find.descendant(of: title, matching: find.byType(RichText)));
  expect(paragraph.didExceedMaxLines, isFalse);
  final toolbar = tester.getRect(find.byType(AppBar));
  expect(titleRect.top, greaterThanOrEqualTo(toolbar.top));
  expect(titleRect.bottom, lessThanOrEqualTo(toolbar.bottom));
  for (final action in ['help', 'records']) {
    expect(_key(action).hitTestable(), findsOneWidget);
    final actionRect = tester.getRect(_key(action));
    expect(actionRect.width, greaterThanOrEqualTo(48));
    expect(actionRect.height, greaterThanOrEqualTo(48));
    expect(titleRect.overlaps(actionRect), isFalse);
  }
}

Future<void> _mount(
  WidgetTester tester,
  _PreviewApi api,
  WalletOperationTestSettings settings,
  GlobalKey boundary,
  _PreviewVariant variant,
) async {
  final operation = testWalletOperation(WalletOperationKind.withdraw, api,
      accountID: 'chain-withdrawal-layout-fixture');
  addTearDown(operation.dispose);
  addTearDown(tester.view.resetViewInsets);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await pumpWalletOperation(
    tester,
    WalletChainWithdrawalScreen(
      coin: withdrawalTestCoin(FundCurrency.usdt),
      payMethod: withdrawalTestMethod(FundCurrency.usdt),
      api: api,
      coordinator: operation,
      accountProvider: () => operation.accountKey,
      settingsService: settings,
      initialAddress: _recipient,
      scanAddress: (_) async => _recipient,
    ),
    size: variant.size,
    brightness: variant.brightness,
    textScale: variant.textScale,
    boundaryKey: boundary,
    fontFamily: _exportPreviews ? 'WalletChainWithdrawalPreviewCjk' : null,
  );
  await _settleAssets(tester);
  expect(_key('loading'), findsNothing);
  expect(_key('error'), findsNothing);
}

Future<void> _fillReadyForm(WidgetTester tester) async {
  await tester.enterText(_key('amount'), '12.5');
  tester.testTextInput.hide();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(_key('network'));
  await tester.tap(_key('network'));
  await tester.pumpAndSettle();
  await tester.tap(_key('network-tron'));
  await tester.pumpAndSettle();
}

void _expectCompleteForm(WidgetTester tester) {
  for (final suffix in [
    'withdrawal-screen',
    'address',
    'paste',
    'scan',
    'network',
    'amount',
    'all',
    'balance',
    'received',
    'fee',
    'total-debit',
    'submit',
  ]) {
    expect(_key(suffix), findsOneWidget);
  }
  expect(tester.widget<Text>(_key('received')).data, '12.5 USDT');
  expect(tester.widget<Text>(_key('fee')).data, '0.25 USDT');
  expect(tester.widget<Text>(_key('total-debit')).data, contains('12.75 USDT'));
  expect(find.text('下一步'), findsNothing);
  expect(find.textContaining('实名认证'), findsNothing);
  _expectNoInformationCard();
}

void _expectNoInformationCard() {
  expect(find.textContaining('链上提现说明'), findsNothing);
  expect(find.byIcon(Icons.account_balance_wallet_outlined), findsNothing);
}

String _inputText(WidgetTester tester, String suffix) => tester
    .widget<TextField>(
        find.descendant(of: _key(suffix), matching: find.byType(TextField)))
    .controller!
    .text;

void _expectNoPayment(_PreviewApi api, WalletOperationTestSettings settings) {
  expect(api.writes, isEmpty);
  expect(settings.statusCalls, 0);
  expect(find.byType(PayPasswordPrompt), findsNothing);
}

Future<void> _loadPreviewFonts() async {
  if (!_exportPreviews) return;
  for (final entry in {
    'WalletChainWithdrawalPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
    'Microsoft YaHei UI': 'C:/Windows/Fonts/msyh.ttc',
    'MaterialIcons':
        'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  }.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    await (FontLoader(entry.key)
          ..addFont(
              Future.value(ByteData.sublistView(await file.readAsBytes()))))
        .load();
  }
}

Future<void> _settleAssets(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(_key('withdrawal-screen'));
    for (final asset in const [
      'lib/pages/wallet/widgets/assets/trx.png',
      'lib/pages/wallet/widgets/assets/usdt.webp',
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _exportFullPage(
    WidgetTester tester, GlobalKey boundary, String name) async {
  if (!_exportPreviews) return;
  final scrollable = tester.state<ScrollableState>(find
      .descendant(of: _key('scroll'), matching: find.byType(Scrollable))
      .first);
  scrollable.position.jumpTo(0);
  final originalSize = tester.view.physicalSize;
  final fullHeight = (originalSize.height + scrollable.position.maxScrollExtent)
      .ceilToDouble();
  try {
    tester.view.physicalSize = Size(originalSize.width, fullHeight);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await _exportCurrent(tester, boundary, '$name-full-page');
  } finally {
    tester.view.physicalSize = originalSize;
    await tester.pumpAndSettle();
  }
}

Future<void> _exportCurrent(
    WidgetTester tester, GlobalKey boundary, String name) async {
  if (!_exportPreviews) return;
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory(_previewDirectory)
        ..createSync(recursive: true);
      await File('${directory.path}/wallet-chain-withdrawal-$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      await File('${directory.path}/preview-notes.txt').writeAsString(
        '真实 Flutter 单页链上提现页面，所有余额、地址、规则和账号均为本地测试夹具。\n'
        '测试不会发起支付，不使用真实账户或交易接口。夹具网络 TRON、币种 USDT。\n'
        '夹具到账本金 12.5 USDT，另收 0.25 USDT 手续费，总扣款 12.75 USDT。\n'
        '亮/暗主题 393×852；小屏 320×852、2 倍文字；键盘遮挡 360dp；横屏 852×393。\n'
        '手续费说明弹窗覆盖亮/暗主题、320×393 小屏大字与 568×320 短横屏大字。\n'
        '已移除链上提现说明卡片；说明弹窗关闭后地址、金额和已选网络保持。\n'
        'full-page 图片临时增高测试视口展示全部内容，生产页面依旧是同一滚动页。\n'
        '键盘图只模拟遮挡与输入焦点，系统键盘本身不绘制在 Flutter 图片中。\n'
        '导出时加载 Microsoft YaHei 与 MaterialIcons；页面资产使用项目测试 AssetBundle。\n',
      );
    } finally {
      image.dispose();
    }
  });
}
