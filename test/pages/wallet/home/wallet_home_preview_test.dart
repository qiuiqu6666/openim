import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/wallet_controller.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';
import 'package:openim/pages/wallet/wallet_tab_shell.dart';

import 'wallet_home_test_support.dart';

// Optional actual-widget preview export, using test-only repository fixtures.
// flutter test test/pages/wallet/home/wallet_home_preview_test.dart
//   --dart-define=WALLET_HOME_PREVIEW_DIR=E:/openim/.temp/wallet-home-refined-preview
const _directory = String.fromEnvironment('WALLET_HOME_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory.isEmpty) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      final bytes = ByteData.sublistView(await font.readAsBytes());
      await (FontLoader('WalletPreviewCjk')..addFont(Future.value(bytes)))
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
    testWidgets('export actual wallet home ${brightness.name} preview',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      final controller = await loadedHomeController();
      await pumpWalletHome(tester,
          controller: controller,
          size: const Size(390, 844),
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletPreviewCjk');
      await tester.pumpAndSettle();
      await settleWalletHomeImages(tester);
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory(_directory)..createSync(recursive: true);
        await File('${output.path}/wallet-home-${brightness.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        await File('${output.path}/preview-notes.txt').writeAsString(
          '钱包首页真实 Flutter Widget 渲染；金额和资产来自仅用于测试的夹具，非真实账户数据。\n'
          'wallet-main-tab-unavailable-* 为实际主Tab壳体及默认未接入钱包后端的状态，金额保持未知。\n'
          '逻辑尺寸 390×844；亮色/暗色；字体 Microsoft YaHei。\n'
          'wallet-home-*-narrow-large 为 320×844、200% 字体的额外窄屏预览。\n'
          'wallet-home-trend-* 为展开态；绿色底线为装饰坐标基线，没有历史资产点。\n',
        );
        image.dispose();
      });
    });

    testWidgets('export real main-tab unavailable ${brightness.name} preview',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      final outerController =
          WalletController(repo: const UnavailableWalletRepository());
      final active = ValueNotifier(3);
      addTearDown(outerController.dispose);
      addTearDown(active.dispose);
      await pumpWalletHome(tester,
          controller: outerController,
          size: const Size(390, 844),
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletPreviewCjk',
          page: WalletTabShell(
              activeTabIndexListenable: active,
              repository: const UnavailableWalletRepository()));
      await tester.pumpAndSettle();
      await settleWalletHomeImages(tester);
      expect(walletHomeKey('wallet-refresh-error'), findsNothing);
      expect(walletHomeKey('wallet-retry'), findsNothing);
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory(_directory)..createSync(recursive: true);
        await File(
                '${output.path}/wallet-main-tab-unavailable-${brightness.name}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });

    testWidgets('export narrow large-text wallet ${brightness.name} preview',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      final controller = await loadedHomeController();
      await pumpWalletHome(tester,
          controller: controller,
          size: const Size(320, 844),
          textScale: 2,
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletPreviewCjk');
      await tester.pumpAndSettle();
      await settleWalletHomeImages(tester);
      expect(tester.takeException(), isNull);
      final render =
          boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory(_directory)..createSync(recursive: true);
        await File(
                '${output.path}/wallet-home-${brightness.name}-narrow-large.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });

    for (final narrow in [false, true]) {
      testWidgets(
          'export expanded trend ${brightness.name}${narrow ? ' narrow large-text' : ''} preview',
          skip: _directory.isEmpty, (tester) async {
        final boundary = GlobalKey();
        final controller = await loadedHomeController();
        await pumpWalletHome(tester,
            controller: controller,
            size: Size(narrow ? 320 : 390, 844),
            textScale: narrow ? 2 : 1,
            brightness: brightness,
            boundaryKey: boundary,
            fontFamily: 'WalletPreviewCjk');
        await tester.pumpAndSettle();
        await tester.tap(walletHomeKey('wallet-action-overview'));
        await tester.pumpAndSettle();
        await settleWalletHomeImages(tester);
        expect(walletHomeKey('wallet-trend-panel'), findsOneWidget);
        expect(walletHomeKey('wallet-trend-empty'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final output = Directory(_directory)..createSync(recursive: true);
          final name =
              'wallet-home-trend-${brightness.name}${narrow ? '-narrow-large' : ''}.png';
          await File('${output.path}/$name')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
