import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim/routes/app_navigator.dart';
import 'package:openim_common/openim_common.dart';

/// Resolve accepted records through the SDK, retaining the request list below.
class RequestHistoryChatOpener {
  bool _opening = false;

  Future<void> open(
      {required String? sourceID,
      required int sessionType,
      required bool Function() isCurrent}) async {
    if (_opening ||
        !isCurrent() ||
        sourceID == null ||
        sourceID.trim().isEmpty) {
      return;
    }
    _opening = true;
    try {
      final conversation = await OpenIM.iMManager.conversationManager
          .getOneConversation(sourceID: sourceID, sessionType: sessionType);
      if (!isCurrent()) return;
      await AppNavigator.startChat(
          conversationInfo: conversation,
          offUntilHome: false,
          isCurrent: isCurrent);
    } catch (_) {
      if (isCurrent()) IMViews.showToast(StrRes.networkError);
    } finally {
      _opening = false;
    }
  }
}
