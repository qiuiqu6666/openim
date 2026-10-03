import 'package:flutter/foundation.dart';

enum AndroidPerformanceTier { low, medium, normal }

class AndroidPerformanceProfile {
  AndroidPerformanceProfile._();

  static final AndroidPerformanceProfile instance = AndroidPerformanceProfile._();

  AndroidPerformanceTier get tier =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? AndroidPerformanceTier.medium
          : AndroidPerformanceTier.normal;
}
