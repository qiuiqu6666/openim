import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:focus_detector_v2/focus_detector_v2.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../core/controller/app_controller.dart';
import '../core/server_nodes/feedback/network_recovery_overlay.dart';

class AppView extends StatelessWidget {
  const AppView({super.key, required this.builder});
  final Widget Function(Locale? locale, TransitionBuilder builder) builder;

  @override
  Widget build(BuildContext context) {
    return GetBuilder<AppController>(
      init: AppController(),
      builder: (ctrl) => FocusDetector(
        onForegroundGained: () => ctrl.runningBackground(false),
        onForegroundLost: () => ctrl.runningBackground(true),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => ctrl.markDeviceSyncUserActivity(),
          onPointerMove: (_) => ctrl.markDeviceSyncUserActivity(),
          onPointerSignal: (_) => ctrl.markDeviceSyncUserActivity(),
          child: ScreenUtilInit(
            designSize: const Size(Config.uiW, Config.uiH),
            minTextAdapt: true,
            splitScreenMode: true,
            fontSizeResolver: (fontSize, _) => fontSize.toDouble(),
            builder: (_, child) => builder(ctrl.getLocale(), _builder()),
          ),
        ),
      ),
    );
  }

  static TransitionBuilder _builder() {
    final builder = EasyLoading.init(
      builder: (context, widget) {
        return AppAccessibilityScope(
          child: AppSystemBars(
            background: Theme.of(context).appBarTheme.backgroundColor ??
                Theme.of(context).colorScheme.surface,
            navigationBackground: Theme.of(context).scaffoldBackgroundColor,
            child: NetworkRecoveryOverlay(child: widget!),
          ),
        );
      },
    );

    configureEasyLoadingInteractions();
    configureEasyLoadingAppearance();
    return builder;
  }
}
