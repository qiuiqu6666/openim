import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppResponsive {
  AppResponsive._();

  static bool isDesktop(BuildContext context) {
    if (kIsWeb) return MediaQuery.sizeOf(context).width >= 900;
    return switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };
  }
}

extension AppResponsiveContextX on BuildContext {
  bool get isDesktopFormFactor => AppResponsive.isDesktop(this);
}
