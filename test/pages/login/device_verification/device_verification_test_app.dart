import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim/widgets/auth/auth_reference.dart';
import 'package:openim_common/openim_common.dart';

bool _hasCjkFont = false;
const devicePreviewDirectory = String.fromEnvironment('DEVICE_PREVIEW_DIR');

Finder get deviceCodeField => find.descendant(
    of: find.byKey(const ValueKey('device-verification-code')),
    matching: find.byType(TextField));
Finder get devicePhoneField => find.descendant(
    of: find.byKey(const ValueKey('device-verification-phone')),
    matching: find.byType(TextField));
Finder get deviceSend => find.byKey(const ValueKey('device-verification-send'));
Finder get deviceConfirm =>
    find.byKey(const ValueKey('device-verification-confirm'));

AuthPrimaryButton deviceConfirmButton(WidgetTester tester) =>
    tester.widget<AuthPrimaryButton>(deviceConfirm);
TextButton deviceSendButton(WidgetTester tester) =>
    tester.widget<TextButton>(deviceSend);

Future<void> loadDevicePreviewFonts() async {
  final font = File('C:/Windows/Fonts/msyh.ttc');
  if (await font.exists()) {
    await (FontLoader('DevicePreviewFont')
          ..addFont(font.readAsBytes().then(ByteData.sublistView)))
        .load();
    _hasCjkFont = true;
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

Future<void> mountDevicePage(
  WidgetTester tester,
  Widget page, {
  bool dark = false,
  Size size = const Size(375, 812),
  double scale = 1,
  double keyboard = 0,
  GlobalKey? boundaryKey,
  List<GetPage<dynamic>> getPages = const [],
}) async {
  configureEasyLoadingInteractions();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  Styles.isDark = dark;
  final brightness = dark ? Brightness.dark : Brightness.light;
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    fontSizeResolver: (fontSize, _) => fontSize.toDouble(),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      translations: TranslationService(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: brightness,
        fontFamily: _hasCjkFont ? 'DevicePreviewFont' : null,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Styles.c_0089FF,
          brightness: brightness,
        ),
      ),
      builder: (context, child) => RepaintBoundary(
        key: boundaryKey,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            viewInsets: EdgeInsets.only(bottom: keyboard),
          ),
          child: EasyLoading.init()(context, child),
        ),
      ),
      home: page,
      getPages: getPages,
    ),
  ));
  await tester.pump();
}

Future<void> clearDevicePage(WidgetTester tester) async {
  // A toast's animation future may schedule its dismissal timer one frame
  // later. Drain it while its overlay is still mounted before disposing it.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 2500));
  await EasyLoading.dismiss(animation: false);
  await tester.pump();
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 2500));
}

Future<void> exportDevicePreview(
    WidgetTester tester, GlobalKey key, String name) async {
  if (devicePreviewDirectory.isEmpty) return;
  await tester.pump();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final rendered = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await rendered.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$devicePreviewDirectory/$name.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      rendered.dispose();
    }
  });
}
