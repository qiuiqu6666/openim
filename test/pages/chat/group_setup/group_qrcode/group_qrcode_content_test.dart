import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/pages/chat/group_setup/group_qrcode/group_qrcode_content.dart';
import 'package:openim_common/openim_common.dart';
import 'package:qr_flutter/qr_flutter.dart';

const _groupName = '三公隔离测试';
const _groupId = 'b5969a8168814c95';
const _qrData = 'io.openim.app/group/@b5969a8168814c95';

Future<void> _showContent(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  Size size = const Size(375, 812),
  double textScale = 1,
  String groupName = _groupName,
  String groupId = _groupId,
  String qrData = _qrData,
  bool saving = false,
  bool scanning = false,
  GlobalKey? cardKey,
  VoidCallback? onSave,
  VoidCallback? onScan,
  VoidCallback? onCopy,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previousDark = Styles.isDark;
  Styles.isDark = brightness == Brightness.dark;
  addTearDown(() => Styles.isDark = previousDark);
  final dark = brightness == Brightness.dark;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        brightness: brightness,
        scaffoldBackgroundColor: AppTokens.background(dark: dark),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SafeArea(
          child: GroupQrcodeContent(
            groupName: groupName,
            groupId: groupId,
            qrData: qrData,
            cardKey: cardKey ?? GlobalKey(),
            saving: saving,
            scanning: scanning,
            onSave: onSave ?? () {},
            onScan: onScan ?? () {},
            onCopy: onCopy ?? () {},
          ),
        ),
      ),
    ),
  ));
  // Loading spinners intentionally remain active while saving.
  await tester.pump(const Duration(milliseconds: 100));
  addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
}

Future<Uint8List> _paintedQrBytes(QrPainter painter) async {
  final image = await painter.toImage(240);
  try {
    final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return pixels!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void main() {
  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  for (final brightness in Brightness.values) {
    testWidgets('invitation card remains scannable in $brightness',
        (tester) async {
      final cardKey = GlobalKey();
      await _showContent(tester, brightness: brightness, cardKey: cardKey);

      expect(find.text(_groupName), findsOneWidget);
      expect(find.text(_groupId), findsOneWidget);
      expect(find.byTooltip('复制群号'), findsOneWidget);
      expect(find.text('该二维码仅用于邀请加入本群'), findsNothing);
      expect(find.text('入群方式以本群设置为准'), findsNothing);
      expect(find.text('保存到相册'), findsOneWidget);
      expect(find.text('扫一扫'), findsOneWidget);

      final code = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(code.backgroundColor, Colors.white);
      expect(code.eyeStyle.color, Colors.black);
      expect(code.dataModuleStyle.color, Colors.black);
      expect(code.embeddedImage, isNull);
      expect(code.padding.left, greaterThanOrEqualTo(16));
      final id = tester.widget<Text>(find.text(_groupId));
      expect(id.maxLines, 1);
      expect(id.overflow, TextOverflow.ellipsis);
      final title = tester.widget<Text>(find.text(_groupName));
      expect(title.style?.color,
          AppTokens.textPrimary(dark: brightness == Brightness.dark));
      expect(id.style?.color,
          AppTokens.textSecondary(dark: brightness == Brightness.dark));
      final codeRect = tester
          .getRect(find.byType(QrImageView))
          .shift(-tester.getTopLeft(find.byKey(cardKey)));
      final boundary =
          cardKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final paintedBlackPixels = await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        try {
          final rgba =
              (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
                  .buffer
                  .asUint8List();
          var blackPixels = 0;
          for (var y = codeRect.top.ceil(); y < codeRect.bottom.floor(); y++) {
            for (var x = codeRect.left.ceil();
                x < codeRect.right.floor();
                x++) {
              final offset = (y * image.width + x) * 4;
              if (rgba[offset] < 32 &&
                  rgba[offset + 1] < 32 &&
                  rgba[offset + 2] < 32 &&
                  rgba[offset + 3] > 240) {
                blackPixels++;
              }
            }
          }
          return blackPixels;
        } finally {
          image.dispose();
        }
      });
      expect(paintedBlackPixels, greaterThan(1500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long identity fits 320px large-text $brightness layout',
        (tester) async {
      final name = List.filled(12, '很长的群名称').join();
      final id = List.filled(12, 'group-public-account-').join();
      var scans = 0;
      await _showContent(
        tester,
        brightness: brightness,
        size: const Size(320, 700),
        textScale: 1.5,
        groupName: name,
        groupId: id,
        onScan: () => scans++,
      );

      expect(find.text(name), findsOneWidget);
      expect(find.text(id), findsOneWidget);
      final codeRect = tester.getRect(find.byType(QrImageView));
      expect(codeRect.left, greaterThanOrEqualTo(0));
      expect(codeRect.right, lessThanOrEqualTo(320));
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('扫一扫'));
      await tester.pumpAndSettle();
      expect(find.text('扫一扫').hitTestable(), findsOneWidget);
      await tester.tap(find.text('扫一扫'));
      await tester.pumpAndSettle();
      expect(scans, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('QR painter encodes the supplied original invitation payload',
      (tester) async {
    const payload = 'io.openim.app/group/@group%2Fid%20with%20spaces';
    await _showContent(tester, qrData: payload);
    final paint = tester.widget<CustomPaint>(find.descendant(
      of: find.byType(QrImageView),
      matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter is QrPainter),
    ));
    final actual = paint.painter! as QrPainter;
    final expected = QrPainter(
      data: payload,
      version: QrVersions.auto,
      gapless: true,
    );
    final bytes = await tester.runAsync(() async => (
          actual: await _paintedQrBytes(actual),
          expected: await _paintedQrBytes(expected),
        ));
    expect(bytes!.actual, orderedEquals(bytes.expected));
    expect(tester.takeException(), isNull);
  });

  testWidgets('copy, save and scan use their existing operation callbacks',
      (tester) async {
    var copies = 0;
    var saves = 0;
    var scans = 0;
    await _showContent(tester,
        onCopy: () => copies++, onSave: () => saves++, onScan: () => scans++);

    await tester.tap(find.byTooltip('复制群号'));
    await tester.ensureVisible(find.text('保存到相册'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存到相册'));
    await tester.ensureVisible(find.text('扫一扫'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('扫一扫'));
    await tester.pumpAndSettle();

    expect(copies, 1);
    expect(saves, 1);
    expect(scans, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'pending operations disable their actions and empty ID disables copy',
      (tester) async {
    var operations = 0;
    await _showContent(tester,
        groupId: '',
        saving: true,
        scanning: true,
        onSave: () => operations++,
        onScan: () => operations++,
        onCopy: () => operations++);

    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull);
    final copy = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '复制群号'));
    expect(copy.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(operations, 0);
    expect(tester.takeException(), isNull);
  });
}
