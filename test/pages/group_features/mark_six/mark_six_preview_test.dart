import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim/pages/group_features/mark_six/pages/mark_six_page.dart';
import 'package:openim/pages/group_features/mark_six/widgets/mark_six_feature_host.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_current_page.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_history_page.dart';
import 'package:openim/pages/group_features/mark_six/agent/pages/agent_descendants_page.dart';
import 'mark_six_fixtures.dart';

final _enabled = Platform.environment['EXPORT_MARK_SIX_PREVIEW'] == '1' ||
    const String.fromEnvironment('EXPORT_MARK_SIX_PREVIEW') == '1';

Future<void> _fonts() async {
  final bytes = ByteData.sublistView(
      await File('C:/Windows/Fonts/msyh.ttc').readAsBytes());
  for (final family in [
    'MarkSixPreviewFont',
    'CupertinoSystemText',
    'CupertinoSystemDisplay'
  ]) {
    await (FontLoader(family)..addFont(Future.value(bytes))).load();
  }
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

ThemeData _theme(bool dark) {
  final brightness = dark ? Brightness.dark : Brightness.light;
  return ThemeData(
      brightness: brightness,
      fontFamily: 'MarkSixPreviewFont',
      colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0089FF),
              brightness: brightness,
              surface: AppTokens.surface(dark: dark))
          .copyWith(onSurface: AppTokens.textPrimary(dark: dark)),
      scaffoldBackgroundColor: AppTokens.background(dark: dark),
      cupertinoOverrideTheme: CupertinoThemeData(
          brightness: brightness,
          primaryColor: CupertinoColors.systemBlue,
          applyThemeToAll: true,
          textTheme: const CupertinoTextThemeData().copyWith(
              textStyle: const TextStyle(
                  fontFamily: 'MarkSixPreviewFont', fontSize: 17),
              actionTextStyle: const TextStyle(
                  fontFamily: 'MarkSixPreviewFont',
                  fontSize: 17,
                  color: CupertinoColors.systemBlue))));
}

Future<void> _mount(
    WidgetTester tester, GlobalKey key, Widget page, bool dark) async {
  Styles.isDark = dark;
  await tester.pumpWidget(ScreenUtilInit(
      designSize: const Size(375, 812),
      builder: (_, __) => RepaintBoundary(
          key: key,
          child: GetMaterialApp(
              debugShowCheckedModeBanner: false,
              translations: TranslationService(),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: _theme(dark),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      padding: const EdgeInsets.only(top: 24, bottom: 24)),
                  child: child!),
              home: page))));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _save(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('docs/previews/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final width in [320.0, 390.0]) {
      testWidgets('export actual Mark Six and agent UI $platform width=$width',
          (tester) async {
        await tester.runAsync(_fonts);
        Get.testMode = true;
        SharedPreferences.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 812);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() {
          Styles.isDark = false;
          Get.reset();
        });
        for (final dark in [false, true]) {
          final platformLabel =
              platform == TargetPlatform.iOS ? 'ios' : 'android';
          final suffix =
              '$platformLabel-${width.toInt()}-${dark ? 'dark' : 'light'}';
          final key = GlobalKey();
          final api = MarkSixFakeApi();
          final c = markSixContext(api);
          await _mount(tester, key, MarkSixPage(featureContext: c), dark);
          await _save(tester, key, 'mark-six-draws-$suffix');
          await tester.tap(find.text('已开统计'));
          await tester.pumpAndSettle();
          await _save(tester, key, 'mark-six-statistics-$suffix');
          await tester.tap(find.text('本群宣言'));
          await tester.pumpAndSettle();
          await _save(tester, key, 'mark-six-declaration-$suffix');
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          if (width == 390) {
            await _mount(
                tester, key, AgentCurrentPage(featureContext: c), dark);
            await _save(tester, key, 'mark-six-agent-current-$suffix');
            await _mount(
                tester, key, AgentHistoryPage(featureContext: c), dark);
            await _save(tester, key, 'mark-six-agent-history-$suffix');
            await _mount(
                tester, key, AgentDescendantsPage(featureContext: c), dark);
            await _save(tester, key, 'mark-six-agent-descendants-$suffix');
            await _mount(
                tester,
                key,
                Scaffold(
                    appBar: AppBar(title: const Text('测试群聊')),
                    body: MarkSixFeatureHost(
                        featureContext: c,
                        builder: (context, entry, overlay) => Stack(children: [
                              const Positioned.fill(
                                  child: Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Text('当前群的聊天内容'))),
                              overlay
                            ]))),
                dark);
            await tester.tap(find.byKey(const ValueKey('lottery-edge-handle')));
            await tester.pumpAndSettle();
            await _save(tester, key, 'mark-six-drawer-$suffix');
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
        }
      }, skip: !_enabled, variant: TargetPlatformVariant({platform}));
    }
  }
}
