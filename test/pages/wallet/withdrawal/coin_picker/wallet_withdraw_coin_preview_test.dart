import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/widgets/platform_coin_icon.dart';

import 'support/wallet_withdraw_coin_test_support.dart';

const _directory = String.fromEnvironment('WALLET_WITHDRAW_PICKER_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory.isEmpty) return;
    for (final entry in {
      'WalletWithdrawCoinPreviewCjk': 'C:/Windows/Fonts/msyh.ttc',
      'MaterialIcons':
          'E:/flutter/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (file.existsSync()) {
        await (FontLoader(entry.key)
              ..addFont(
                  Future.value(ByteData.sublistView(await file.readAsBytes()))))
            .load();
      }
    }
  });

  for (final brightness in Brightness.values) {
    for (final variant in ['list', 'search', 'large-keyboard']) {
      testWidgets('export withdrawal coin picker $variant ${brightness.name}',
          skip: _directory.isEmpty, (tester) async {
        final boundary = GlobalKey();
        final large = variant == 'large-keyboard';
        await pumpWalletWithdrawCoins(tester,
            kind: WithdrawTransferTargetKind.chain,
            boundaryKey: boundary,
            brightness: brightness,
            size: Size(large ? 320 : 390, 844),
            textScale: large ? 2 : 1,
            fontFamily: 'WalletWithdrawCoinPreviewCjk');
        if (variant != 'list') await searchWithdrawCoins(tester, 'trx');
        if (large) {
          tester.view.viewInsets = const FakeViewPadding(bottom: 360);
        }
        await tester.runAsync(() async {
          final context = tester.element(withdrawCoinKey('picker'));
          for (final asset in [
            'lib/pages/wallet/widgets/assets/trx.png',
            'lib/pages/wallet/widgets/assets/usdt.webp',
            PlatformCoinIcon.assetPath,
          ]) {
            await precacheImage(AssetImage(asset), context);
          }
        });
        await tester.pumpAndSettle();
        expect(withdrawCoinKey('picker'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _export(tester, boundary,
            'wallet-withdraw-coins-$variant-${brightness.name}.png');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

Future<void> _export(
    WidgetTester tester, GlobalKey boundary, String name) async {
  final render =
      boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await render.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final output = Directory(_directory)..createSync(recursive: true);
      await File('${output.path}/$name')
          .writeAsBytes(bytes!.buffer.asUint8List());
      await File('${output.path}/preview-notes.txt')
          .writeAsString('真实 Flutter 提现选币页面；币种、余额、法币估值均为注入测试夹具，非真实账户。\n'
              '搜索匹配代码、服务端名称和展示名称；没有访问网络、联系人或提交提现。\n'
              '亮/暗主题，390×844；大字/键盘为 320×844，2 倍文字，360dp 键盘遮挡模拟。\n'
              'Microsoft YaHei；真实系统键盘画面没有绘制到 Flutter 截图中。\n');
    } finally {
      image.dispose();
    }
  });
}
