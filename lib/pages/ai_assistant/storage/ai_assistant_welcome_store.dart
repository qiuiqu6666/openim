import 'package:openim_common/openim_common.dart';

/// Only presentation preferences are stored locally; AI history stays server-owned.
class AiAssistantWelcomeStore {
  AiAssistantWelcomeStore._();
  static String keyFor(String userId) => 'ai_assistant_welcome_dismissed_${Uri.encodeComponent(userId.trim())}';
  static String guideKeyFor(String userId) => 'ai_assistant_guide_dismissed_${Uri.encodeComponent(userId.trim())}';
  static Future<bool> isDismissed(String userId) async => userId.trim().isNotEmpty && (SpUtil().getBool(keyFor(userId)) ?? false);
  static Future<bool> isGuideDismissed(String userId) async => userId.trim().isEmpty || (SpUtil().getBool(guideKeyFor(userId)) ?? false);
  static Future<void> dismiss(String userId) async {
    if (userId.trim().isNotEmpty) await SpUtil().putBool(keyFor(userId), true);
  }
  static Future<void> dismissGuide(String userId) async {
    if (userId.trim().isNotEmpty) await SpUtil().putBool(guideKeyFor(userId), true);
  }
}
