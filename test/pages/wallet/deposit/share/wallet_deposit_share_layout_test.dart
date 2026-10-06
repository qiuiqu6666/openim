import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openim/pages/wallet/data/wallet_fund_api.dart';
import 'package:openim/pages/wallet/deposit/share/wallet_deposit_share_tokens.dart';
import 'package:openim/pages/wallet/deposit/widgets/wallet_deposit_share_preview.dart';
import 'package:openim/pages/wallet/wallet_share_service.dart';

import '../support/wallet_deposit_qr_expectation.dart';
import '../support/wallet_deposit_test_support.dart';

const _directory = String.fromEnvironment('WALLET_DEPOSIT_SHARE_PREVIEW_DIR');
const _fontFamily = 'WalletDepositSharePreviewCjk';
const _scenarios = [
  (
    name: 'light',
    brightness: Brightness.light,
    size: Size(390, 844),
    textScale: 1.0,
    currency: FundCurrency.usdt,
    compact: false,
  ),
  (
    name: 'dark',
    brightness: Brightness.dark,
    size: Size(390, 844),
    textScale: 1.0,
    currency: FundCurrency.trx,
    compact: false,
  ),
  (
    name: 'large-text',
    brightness: Brightness.light,
    size: Size(320, 650),
    textScale: 2.0,
    currency: FundCurrency.usdt,
    compact: true,
  ),
  (
    name: 'landscape',
    brightness: Brightness.light,
    size: Size(844, 390),
    textScale: 1.0,
    currency: FundCurrency.trx,
    compact: true,
  ),
];

Finder _inside(Finder parent, Finder child) =>
    find.descendant(of: parent, matching: child);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory.isEmpty) return;
    for (final entry in {
      _fontFamily: 'C:/Windows/Fonts/msyh.ttc',
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
  });

  for (final scenario in _scenarios) {
    testWidgets('deposit share separates card and two actions ${scenario.name}',
        (tester) async {
      final previousShadows = debugDisableShadows;
      addTearDown(() => debugDisableShadows = previousShadows);
      if (_directory.isNotEmpty) debugDisableShadows = true;
      try {
        final appBoundary = GlobalKey();
        final service = DepositTestShareService();
        await pumpWalletDeposit(tester,
            api: WalletTestFundApi(),
            share: service,
            currency: scenario.currency,
            brightness: scenario.brightness,
            size: scenario.size,
            textScale: scenario.textScale,
            appBoundaryKey: appBoundary,
            fontFamily: _directory.isEmpty ? null : _fontFamily);
        await _settleImages(tester);
        await tester.ensureVisible(depositKey('wallet-deposit-share'));
        await tester.tap(depositKey('wallet-deposit-share'));
        await tester.pumpAndSettle();
        final overlay = depositKey('wallet-deposit-share-sheet');
        final actions = depositKey('wallet-deposit-share-actions');
        final cancel = depositKey('wallet-deposit-share-cancel');
        final preview = find.byType(WalletDepositSharePreview);
        final qr = _inside(preview, depositKey('wallet-deposit-qr'));
        final cardColor = WalletDepositShareTokens.cardColor(
            dark: scenario.brightness == Brightness.dark);
        expect(overlay, findsOneWidget);
        expect(actions, findsOneWidget);
        expect(preview, findsOneWidget);
        expect(cancel, findsOneWidget);
        expect(
            Theme.of(tester.element(overlay)).brightness, scenario.brightness);
        expect(_inside(preview, find.text('99Chat')), findsOneWidget);
        expect(
            _inside(preview, find.text('将${scenario.currency.code}充值到99Chat')),
            findsOneWidget);
        expect(_inside(preview, find.text('TRON')), findsOneWidget);
        expect(
            tester
                .widget<Text>(depositKey('wallet-deposit-share-address'))
                .data,
            testDepositAddress);
        expect(
            tester
                .widget<Text>(depositKey('wallet-deposit-share-created-at'))
                .data,
            matches(RegExp(r'^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}$')));
        for (final key in [
          'wallet-deposit-copy',
          'wallet-deposit-wechat',
          'wallet-deposit-qq',
          'wallet-deposit-sms',
        ]) {
          expect(_inside(overlay, depositKey(key)), findsNothing);
        }
        for (final label in ['复制地址', 'WeChat', 'QQ', '短信', '更多']) {
          expect(_inside(overlay, find.text(label)), findsNothing);
        }
        expect(_inside(actions, find.text('保存图片')), findsOneWidget);
        expect(_inside(actions, find.text('分享')), findsOneWidget);
        expect(_inside(actions, depositKey('wallet-deposit-save')),
            findsOneWidget);
        expect(_inside(actions, depositKey('wallet-deposit-system-share')),
            findsOneWidget);
        expect(_inside(actions, cancel), findsNothing);
        expect(_inside(actions, preview), findsNothing);
        expect(_inside(preview, find.byType(OutlinedButton)), findsNothing);
        expect(_inside(preview, actions), findsNothing);
        expect(tester.getRect(actions).bottom,
            lessThanOrEqualTo(tester.getRect(cancel).top));
        if (!scenario.compact) {
          expect(tester.getRect(preview).bottom,
              lessThan(tester.getRect(actions).top));
        } else {
          final viewport = find
              .ancestor(of: preview, matching: find.byType(Scrollable))
              .first;
          final rect = tester.getRect(viewport);
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(tester.getRect(actions).top));
          expect(rect.right, lessThanOrEqualTo(scenario.size.width));
        }
        for (final key in [
          'wallet-deposit-save',
          'wallet-deposit-system-share',
          'wallet-deposit-share-cancel',
        ]) {
          expect(depositKey(key).hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        final cardBoundary = find
            .ancestor(of: preview, matching: find.byType(RepaintBoundary))
            .first;
        if (_directory.isNotEmpty) {
          await _exportOverlay(
              tester,
              appBoundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary,
              'wallet-deposit-share-overlay-${scenario.name}.png');
          final boundaryKey =
              tester.widget<RepaintBoundary>(cardBoundary).key! as GlobalKey;
          await _exportSavedCard(tester, boundaryKey, qr, cardColor,
              'wallet-deposit-share-card-${scenario.name}.png');
        }
        if (scenario.compact) {
          final viewport = find
              .ancestor(of: preview, matching: find.byType(Scrollable))
              .first;
          final position = tester.state<ScrollableState>(viewport).position;
          final actionsRect = tester.getRect(actions);
          expect(position.maxScrollExtent, greaterThan(0));
          final before = position.pixels;
          for (var i = 0;
              i < 8 && position.pixels < position.maxScrollExtent - .5;
              i++) {
            await tester.drag(
                viewport, Offset(0, -tester.getSize(viewport).height * .8));
            await tester.pumpAndSettle();
          }
          expect(position.pixels, greaterThan(before));
          expect(position.pixels, closeTo(position.maxScrollExtent, .5));
          final footer =
              tester.getRect(depositKey('wallet-deposit-share-address'));
          final visibleRect = tester.getRect(viewport);
          expect(footer.top, greaterThanOrEqualTo(visibleRect.top - .5));
          expect(footer.bottom, lessThanOrEqualTo(visibleRect.bottom + .5),
              reason: 'Dragging the preview must expose the complete address');
          expect(tester.getRect(actions), actionsRect,
              reason: 'Card scrolling must keep save/share actions in place');
        }
        await tester.tap(depositKey('wallet-deposit-save'));
        await tester.pumpAndSettle();
        expect(service.saves, hasLength(1));
        expect(service.saveBackgrounds, [cardColor]);
        final capturedCard = find.byKey(service.saves.single);
        expect(_inside(capturedCard, actions), findsNothing);
        expect(_inside(capturedCard, cancel), findsNothing);
        expect(await decodeDepositRenderedQr(tester, service.saves.single, qr),
            testDepositAddress,
            reason: 'The real card sent to gallery must retain a scannable QR');
        await EasyLoading.dismiss(animation: false);
        await tester.pumpAndSettle();
        await tester.tap(depositKey('wallet-deposit-system-share'));
        await tester.pumpAndSettle();
        expect(service.imageShares, [service.saves.single]);
        expect(service.imageShareBackgrounds, [cardColor]);
        expect(service.shares, isEmpty);
        expect(service.messages, isEmpty);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(overlay, findsNothing);
        expect(depositKey('wallet-deposit-address'), findsOneWidget);
        await tester.ensureVisible(depositKey('wallet-deposit-address-copy'));
        await tester.tap(depositKey('wallet-deposit-address-copy'));
        await tester.pumpAndSettle();
        expect(service.copies, [testDepositAddress]);
        expect(tester.takeException(), isNull);
        await EasyLoading.dismiss(animation: false);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        // Flutter checks this invariant before addTearDown callbacks execute.
        debugDisableShadows = previousShadows;
      }
    });
  }
}

Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    final context = tester.element(depositKey('wallet-deposit-share'));
    for (final asset in const [
      'lib/pages/wallet/widgets/assets/trx.png',
      'lib/pages/wallet/widgets/assets/usdt.webp',
      'assets/img/99chat_logo.png',
    ]) {
      await precacheImage(AssetImage(asset), context);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _exportOverlay(
    WidgetTester tester, RenderRepaintBoundary render, String name) async {
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!.buffer.asUint8List();
      final output = Directory(_directory)..createSync(recursive: true);
      await File('${output.path}/$name').writeAsBytes(bytes);
      await File('${output.path}/preview-notes.txt')
          .writeAsString('真实 Flutter 充值分享弹窗与实际保存/分享卡片。\n'
              '地址与网络来自注入的测试夹具，非真实账户；二维码解码与夹具地址一致。\n'
              '99Chat 品牌、本次打开时间；仅保存图片/分享两个动作，取消独立，复制保留在充值页面。\n'
              '亮暗 390×844；大字 320×650、2倍文字；横屏 844×390。\n'
              'overlay 为2倍渲染截图；card为原生保存服务实际发送的3倍PNG，全部像素不透明、四角与卡片背景一致。\n'
              'PNG及模拟Android图库JPEG转码后二维码均可解码为同一地址。\n'
              'Microsoft YaHei 与 MaterialIcons；仅为稳定 PNG 渲染关闭测试阴影。\n');
    } finally {
      image.dispose();
    }
  });
}

Future<void> _exportSavedCard(WidgetTester tester, GlobalKey boundaryKey,
    Finder qr, Color background, String name) async {
  const gallery = MethodChannel('image_gallery_saver_plus');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final render =
      boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final qrRect = tester.getRect(qr).shift(-render.localToGlobal(Offset.zero));
  Uint8List? savedBytes;
  var galleryCalls = 0;
  messenger.setMockMethodCallHandler(gallery, (call) async {
    galleryCalls++;
    final arguments = call.arguments as Map;
    savedBytes = arguments['imageBytes'] as Uint8List;
    expect(arguments['quality'], 100);
    return {'isSuccess': true};
  });
  try {
    await tester.runAsync(() async {
      final service =
          WalletShareService(requestPhotoPermission: (_) async => true);
      final result = await service.saveQrImg(
          boundaryKey.currentContext!, boundaryKey,
          isCurrent: () => boundaryKey.currentContext?.mounted == true,
          backgroundColor: background);
      expect(result, WalletSaveImgResult.success);
      expect(galleryCalls, 1);
      expect(savedBytes, isNotNull);
      final bytes = savedBytes!;
      final png = img.decodePng(bytes)!;
      expect(png.width, closeTo(render.size.width * 3, 1));
      expect(png.height, closeTo(render.size.height * 3, 1));
      expect(png.every((pixel) => pixel.a == 255), isTrue,
          reason: 'Native gallery PNG must contain no transparent edge pixels');
      final rgb = background.toARGB32();
      final expected = [(rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255];
      for (final corner in [
        (0, 0),
        (png.width - 1, 0),
        (0, png.height - 1),
        (png.width - 1, png.height - 1),
      ]) {
        final pixel = png.getPixel(corner.$1, corner.$2);
        expect([pixel.r, pixel.g, pixel.b, pixel.a], expected,
            reason: 'Rounded PNG corners must use the current card background');
      }
      expect(
          decodeDepositPngQr(bytes, qrRect, pixelRatio: 3), testDepositAddress,
          reason: 'Native gallery PNG must scan to the real fixture address');
      final jpeg = img.decodeJpg(img.encodeJpg(png, quality: 100))!;
      final jpegAsPng = Uint8List.fromList(img.encodePng(jpeg));
      expect(decodeDepositPngQr(jpegAsPng, qrRect, pixelRatio: 3),
          testDepositAddress,
          reason: 'Android gallery JPEG conversion must keep the QR scannable');
      final output = Directory(_directory)..createSync(recursive: true);
      await File('${output.path}/$name').writeAsBytes(bytes);
    });
  } finally {
    messenger.setMockMethodCallHandler(gallery, null);
  }
}
