import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'feedback_colors.dart';

void configureEasyLoadingAppearance() {
  EasyLoading.instance
    ..indicatorSize = 50
    ..backgroundColor = FeedbackColors.background
    ..indicatorColor = FeedbackColors.foreground
    ..progressColor = FeedbackColors.foreground
    ..progressWidth = 6.0
    ..textColor = FeedbackColors.foreground
    ..loadingStyle = EasyLoadingStyle.custom
    ..indicatorType = EasyLoadingIndicatorType.fadingCircle;
}
