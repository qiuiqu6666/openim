import 'dart:async';
import 'package:country_picker/country_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'core/controller/im_controller.dart';
import 'core/server_nodes/automatic_node_runtime.dart';
import 'core/server_nodes/startup/startup_network_preparation.dart';
import 'core/controller/app_controller.dart';
import 'core/user_activity/activity_runtime.dart';
import 'routes/app_pages.dart';
import 'routes/swipe_back/app_get_transition.dart';
import 'routes/swipe_back/app_swipe_back_tokens.dart';
import 'theme/app_theme_controller.dart';
import 'theme/app_theme_data.dart';
import 'theme/app_scroll_behavior.dart';
import 'widgets/app_view.dart';
import 'services/messaging/browser_link_share.dart';
import 'services/media_recognition/media_image_recognition_host.dart';
import 'package:openim_common/media_recognition.dart';

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AppView(
      builder: (locale, builder) => ListenableBuilder(
        listenable: AppThemeController.instance,
        builder: (context, _) => GetMaterialApp(
          debugShowCheckedModeBanner: false,
          scrollBehavior: const AppScrollBehavior(),
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
            CountryLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          fallbackLocale: TranslationService.fallbackLocale,
          locale: locale,
          localeResolutionCallback: (locale, list) {
            return TranslationService.resolveLocale(locale);
          },
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('zh', 'TW'),
            Locale('en', 'US')
          ],
          getPages: AppPages.routes,
          customTransition: AppGetTransition(),
          popGesture: false,
          transitionDuration: AppSwipeBackTokens.transitionDuration,
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
    InAppBrowserShare.send = shareBrowserLink;
    MediaImageRecognition.start = recognizePreviewImage;
    final network = Get.put(StartupNetworkPreparation());
    Get.put<IMController>(IMController(
        prepareStartup: network.prepare, onStartupFailure: network.sdkFailed));
    Get.put<AutomaticNodeRuntime>(
        AutomaticNodeRuntime(startupReady: () => network.handoffComplete));
    Get.put<PushController>(PushController());
    Get.put<CacheController>(CacheController());
  }
}
