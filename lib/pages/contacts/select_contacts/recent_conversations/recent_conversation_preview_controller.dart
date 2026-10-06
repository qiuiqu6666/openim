import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../core/controller/im_controller.dart';
import '../../../conversation/conversation_logic.dart';
import 'recent_conversation_preview.dart';

/// Owned by the existing recipient selection controller, with no SDK listeners.
class RecentConversationPreviewController {
  RecentConversationPreviewController() {
    final im =
        Get.isRegistered<IMController>() ? Get.find<IMController>() : null;
    if (im != null) {
      _subscriptions.add(im.revokedMessages.listen((_) => _invalidate()));
      _subscriptions.add(im.deletedMessages.listen((_) => _invalidate()));
    }
  }

  final _accountID = OpenIM.iMManager.userID;
  final _token = DataSp.chatToken;
  final _conversations = Get.isRegistered<ConversationLogic>()
      ? Get.find<ConversationLogic>()
      : null;
  final _revision = 0.obs;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _closed = false;

  bool get _inactive =>
      _closed ||
      OpenIM.iMManager.userID != _accountID ||
      DataSp.chatToken != _token;

  void _invalidate() {
    if (!_inactive) _revision.value++;
  }

  String text(ConversationInfo snapshot) => data(snapshot).text;

  RecentConversationPreviewData data(ConversationInfo snapshot) {
    // The shared tombstone cache is not reactive; its existing events are.
    _revision.value;
    if (_inactive) return const RecentConversationPreviewData();
    final conversations = _conversations;
    if (conversations == null) return recentConversationPreviewData(snapshot);
    if (conversations.isClosed || !conversations.isSessionActive) {
      return const RecentConversationPreviewData();
    }
    final latest = conversations.list.firstWhereOrNull(
        (item) => item.conversationID == snapshot.conversationID);
    // A removed live conversation must not expose the old selection snapshot.
    return recentConversationPreviewData(latest);
  }

  void dispose() {
    _closed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }
}
