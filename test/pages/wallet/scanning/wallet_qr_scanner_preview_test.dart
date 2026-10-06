import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/wallet_scanner_fixture.dart';

final _directory = Platform.environment['WALLET_QR_SCANNER_PREVIEW'] ??
    const String.fromEnvironment('WALLET_QR_SCANNER_PREVIEW');
final _previewCase = Platform.environment['WALLET_QR_SCANNER_PREVIEW_CASE'] ??
    const String.fromEnvironment('WALLET_QR_SCANNER_PREVIEW_CASE');

bool _includes(String name) => _previewCase.isEmpty || _previewCase == name;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(initializeWalletScannerTests);

  testWidgets('export actual wallet scanner widgets', (tester) async {
    if (_previewCase.isNotEmpty) {
      expect(const [
        'light-normal',
        'dark-normal',
        'light-small-large-text',
        'dark-small-large-text',
        'light-landscape-large-text',
        'dark-landscape-large-text',
        'ja-small-large-text',
      ], contains(_previewCase));
    }
    await tester.runAsync(() async {
      final font = File('C:/Windows/Fonts/msyh.ttc');
      if (await font.exists()) {
        final data = ByteData.sublistView(await font.readAsBytes());
        await (FontLoader('WalletScannerPreview')..addFont(Future.value(data)))
            .load();
      }
      await (FontLoader('MaterialIcons')
            ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
          .load();
      await Directory(_directory).create(recursive: true);
    });
    for (final dark in [false, true]) {
      for (final (name, size, scale) in const [
        ('normal', Size(390, 844), 1.0),
        ('small-large-text', Size(320, 568), 2.0),
        ('landscape-large-text', Size(568, 320), 2.0),
      ]) {
        final caseName = '${dark ? 'dark' : 'light'}-$name';
        if (!_includes(caseName)) continue;
        final h = WalletScannerHost(tester);
        try {
          await h.mount(
              dark: dark,
              size: size,
              textScale: scale,
              previewFont: 'WalletScannerPreview',
              padding: size.width > size.height
                  ? const EdgeInsets.fromLTRB(44, 24, 16, 16)
                  : const EdgeInsets.only(top: 24, bottom: 20));
          await tester.pump(const Duration(milliseconds: 16));
          final boundary = h.previewKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              await File('$_directory/wallet-scanner-$caseName.png')
                  .writeAsBytes(data!.buffer.asUint8List());
            } finally {
              image.dispose();
            }
          });
          expect(tester.takeException(), isNull);
        } finally {
          await h.close();
        }
      }
    }
    if (!_includes('ja-small-large-text')) return;
    final japanese = WalletScannerHost(tester);
    try {
      await japanese.mount(
          locale: const Locale('ja'),
          size: const Size(320, 568),
          textScale: 2,
          previewFont: 'WalletScannerPreview');
      await tester.pump(const Duration(milliseconds: 16));
      final boundary = japanese.previewKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$_directory/wallet-scanner-ja-small-large-text.png')
              .writeAsBytes(data!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      expect(tester.takeException(), isNull);
    } finally {
      await japanese.close();
    }
  }, skip: _directory.isEmpty);
}
