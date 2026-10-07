import 'package:flutter/cupertino.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'core/controller/im_controller.dart';
import 'core/controller/app_controller.dart';
import 'core/user_activity/activity_runtime.dart';
import 'routes/app_pages.dart';
import 'theme/app_theme_controller.dart';
import 'widgets/app_view.dart';

class ChatApp extends StatelessWidget {
  const ChatApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AppView(
      builder: (locale, builder) => ListenableBuilder(
        listenable: AppThemeController.instance,
        builder: (context, _) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorObservers: [ActivityRuntime.instance.observer],
          enableLog: true,
          routingCallback: (_) {
            if (Get.isRegistered<AppController>()) {
              final controller = Get.find<AppController>();
              controller.markDeviceSyncUserActivity();
              unawaited(controller.onApplicationSessionReady());
            }
          },
          builder: builder,
          translations: TranslationService(),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          fallbackLocale: TranslationService.fallbackLocale,
          locale: locale,
          localeResolutionCallback: (locale, list) {
            Get.locale ??= locale;
            return locale;
          },
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          getPages: AppPages.routes,
          initialBinding: InitBinding(),
          initialRoute: AppRoutes.splash,
          theme: _themeData(Brightness.light),
          darkTheme: _themeData(Brightness.dark),
          themeMode: AppThemeController.instance.mode,
        ),
      ),
    );
  }

  ThemeData _themeData(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? const Color(0xFF202A36) : Colors.white;
    final foreground = dark ? const Color(0xFFE8EDF5) : const Color(0xFF0C1C33);
    final base = ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF0089FF),
              brightness: brightness,
              surface: surface)
          .copyWith(onSurface: foreground),
    );
    return base.copyWith(
      scaffoldBackgroundColor:
          dark ? const Color(0xFF141D27) : const Color(0xFFF8F9FA),
      canvasColor: surface,
      cardColor: surface,
      appBarTheme: AppBarTheme(
          backgroundColor: surface,
          foregroundColor: foreground,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          systemOverlayStyle: AppSystemBars.styleFor(surface)),
      textSelectionTheme:
          const TextSelectionThemeData().copyWith(cursorColor: Colors.blue),
      checkboxTheme: const CheckboxThemeData().copyWith(
        checkColor: WidgetStateProperty.all(Colors.white),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return Colors.grey;
          }
          if (states.contains(WidgetState.selected)) {
            return Colors.blue;
          }
          return Colors.white;
        }),
        side: BorderSide(color: Colors.grey.shade500, width: 1),
      ),
      dialogTheme: const DialogThemeData().copyWith(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4.0),
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 16.sp,
              color: foreground,
            ),
          ),
          foregroundColor: WidgetStatePropertyAll(foreground),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData().copyWith(
          color: Colors.white,
          linearTrackColor: Colors.grey[300],
          circularTrackColor: Colors.grey[300]),
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: CupertinoColors.systemBlue,
        barBackgroundColor: surface,
        applyThemeToAll: true,
        textTheme: const CupertinoTextThemeData().copyWith(
          navActionTextStyle:
              TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
          actionTextStyle:
              TextStyle(color: CupertinoColors.systemBlue, fontSize: 17.sp),
          textStyle: TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
          navLargeTitleTextStyle:
              TextStyle(color: CupertinoColors.label, fontSize: 20.sp),
          navTitleTextStyle:
              TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
          pickerTextStyle:
              TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
          tabLabelTextStyle:
              TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
          dateTimePickerTextStyle:
              TextStyle(color: CupertinoColors.label, fontSize: 17.sp),
        ),
      ),
    );
  }
}

class InitBinding extends Bindings {
  @override
  void dependencies() {
    Get.put<IMController>(IMController());
    Get.put<PushController>(PushController());
    Get.put<CacheController>(CacheController());
  }
}
