import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/wallet/wallet_repository.dart';

import 'support/wallet_record_test_support.dart';

// Optional screenshots of the actual production widget with test-only records.
// flutter test test/pages/wallet/record/wallet_record_preview_test.dart
//   --dart-define=WALLET_RECORD_PREVIEW_DIR=E:/openim/.temp/wallet-record-preview
const _directory = String.fromEnvironment('WALLET_RECORD_PREVIEW_DIR');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (_directory.isEmpty) return;
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      await (FontLoader('WalletRecordPreviewCjk')
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
    testWidgets('export fixture ledger ${brightness.name} preview',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      await pumpWalletRecords(tester,
          repository: RecordTestRepository(),
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletRecordPreviewCjk');
      await settleWalletRecordImages(tester);
      expect(walletRecordKey('wallet-record-month-2026-10'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _export(tester, boundary, 'wallet-record-${brightness.name}.png');
    });

    testWidgets('export unavailable empty ledger ${brightness.name} preview',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      await pumpWalletRecords(tester,
          repository: const UnavailableWalletRepository(),
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletRecordPreviewCjk');
      await settleWalletRecordImages(tester);
      expect(walletRecordKey('wallet-record-empty'), findsOneWidget);
      expect(find.text('暂无记录'), findsOneWidget);
      expect(walletRecordKey('wallet-record-error'), findsNothing);
      expect(tester.takeException(), isNull);
      await _export(
          tester, boundary, 'wallet-record-empty-${brightness.name}.png');
    });

    testWidgets('export 320px large-text ledger ${brightness.name} preview',
        skip: _directory.isEmpty, (tester) async {
      final boundary = GlobalKey();
      await pumpWalletRecords(tester,
          repository: RecordTestRepository(),
          size: const Size(320, 844),
          textScale: 2,
          brightness: brightness,
          boundaryKey: boundary,
          fontFamily: 'WalletRecordPreviewCjk');
      await settleWalletRecordImages(tester);
      expect(walletRecordKey('wallet-record-month-2026-10'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _export(tester, boundary,
          'wallet-record-${brightness.name}-narrow-large.png');
    });
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
      await File('${output.path}/preview-notes.txt').writeAsString(
        '余额变动明细真实 Flutter Widget 渲染；记录为测试夹具，非真实账户数据。\n'
        '金额显示两位小数；余额没有后端字段，显示 --；无虚构商家。\n'
        'wallet-record-empty-* 为默认未接入后端的空记录状态，不填测试交易。\n'
        '亮色/暗色；390×844；Microsoft YaHei。\n'
        'narrow-large 为 320×844、200% 字体预览；六图共覆盖真实记录、空记录及窄屏大字。\n',
      );
    } finally {
      image.dispose();
    }
  });
}
