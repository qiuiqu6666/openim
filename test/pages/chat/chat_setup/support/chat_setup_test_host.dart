import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

final chatSetupPreviewDirectory =
    Platform.environment['CHAT_SETUP_PREVIEW_DIR'] ?? '';

Future<void> initializeChatSetupUi() async {
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
  await DataSp.init();
  Get.testMode = true;
  await NavigationGlassController.instance
      .setMode(NavigationGlassMode.translucent);
  if (chatSetupPreviewDirectory.isEmpty) return;
  final font = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final family in [
    'ChatSetupPreview',
    'CupertinoSystemText',
    'CupertinoSystemDisplay',
  ]) {
    await (FontLoader(family)..addFont(Future.value(font))).load();
  }
  final icons = File('E:/flutter/flutter/bin/cache/artifacts/material_fonts/'
      'MaterialIcons-Regular.otf');
  await (FontLoader('MaterialIcons')
        ..addFont(
            Future.value(ByteData.sublistView(await icons.readAsBytes()))))
      .load();
}

Future<GlobalKey> mountChatSetupUi(WidgetTester tester, Widget page,
    {bool dark = false,
    Size size = const Size(375, 812),
    double scale = 1,
    bool showBackButton = false,
    TargetPlatform platform = TargetPlatform.iOS}) async {
  final previousDark = Styles.isDark;
  Styles.isDark = dark;
  addTearDown(() => Styles.isDark = previousDark);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final previewKey = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: previewKey,
    child: ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        translations: TranslationService(),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          platform: platform,
          fontFamily:
              chatSetupPreviewDirectory.isEmpty ? null : 'ChatSetupPreview',
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
            viewPadding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: showBackButton ? const Scaffold() : page,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  if (showBackButton) {
    Get.to(() => page, transition: Transition.noTransition);
    await tester.pumpAndSettle();
  }
  return previewKey;
}

Future<void> exportChatSetupUi(
    WidgetTester tester, GlobalKey key, String name) async {
  if (chatSetupPreviewDirectory.isEmpty) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  void repaint(RenderObject object) {
    object.visitChildren(repaint);
    object.markNeedsPaint();
  }

  repaint(boundary);
  await tester.pump();
  await tester.runAsync(() async {
    final snapshot = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await snapshot.toByteData(format: ui.ImageByteFormat.png);
      final target = File('$chatSetupPreviewDirectory/$name.png');
      await target.parent.create(recursive: true);
      await target.writeAsBytes(data!.buffer.asUint8List());
    } finally {
      snapshot.dispose();
    }
  });
}
