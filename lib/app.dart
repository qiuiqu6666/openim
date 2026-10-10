import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'core/controller/im_controller.dart';
import 'core/controller/app_controller.dart';
import 'core/user_activity/activity_runtime.dart';
import 'routes/app_pages.dart';
import 'theme/app_theme_controller.dart';
import 'theme/app_theme_data.dart';
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
          theme: buildAppThemeData(Brightness.light),
          darkTheme: buildAppThemeData(Brightness.dark),
          themeMode: AppThemeController.instance.mode,
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
