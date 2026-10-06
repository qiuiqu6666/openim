import 'package:get/get.dart';

/// Supplemental copy follows the app's existing Chinese/English locale.
String authText(String zh, String en) =>
    Get.locale?.languageCode == 'en' ? en : zh;
