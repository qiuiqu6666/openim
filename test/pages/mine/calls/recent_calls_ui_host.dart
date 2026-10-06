import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> mountRecentCalls(WidgetTester tester, Widget page,
    {bool dark = false,
    Size size = const Size(375, 812),
    double textScale = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (_, __) => GetMaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: dark ? Brightness.dark : Brightness.light,
        platform: TargetPlatform.iOS,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
          viewPadding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: page,
    ),
  ));
  await tester.pump();
  await tester.idle();
  await tester.pump();
}

Future<void> initializeRecentCallsUi() async {
  SharedPreferences.setMockInitialValues({});
  await SpUtil().init();
  Get.testMode = true;
  await NavigationGlassController.instance
      .setMode(NavigationGlassMode.translucent);
}
