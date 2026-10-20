import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../routes/app_navigator.dart';
import '../../contacts/select_contacts/recent_conversations/recent_conversation_directory.dart';
import '../../contacts/select_contacts/selection/contact_selection_policy.dart';
import '../../conversation/conversation_logic.dart';
import '../messages/forwarding/pending_forward.dart';

/// One preview session owns its recipient snapshot. No message is sent here.
class ChatMediaShareRecipients {
  ChatMediaShareRecipients({required this.isCurrent});
  final bool Function() isCurrent;
  final _rows = <String, ConversationInfo>{};
  bool _staging = false;

  Future<List<MediaShareRecipient>> load() async {
    if (!isCurrent() || !Get.isRegistered<ConversationLogic>()) return [];
    final directory = RecentConversationDirectory.sdk();
    final result = await directory.load(
        Get.find<ConversationLogic>().list.take(20).toList(),
        isVisible: (row) =>
            ContactSelectionPolicy.allows(row) &&
            (row.isSingleChat || row.isGroupChat),
        isCurrent: isCurrent);
    if (!isCurrent()) return [];
    if (result.failed && result.rows.isEmpty) {
      throw StateError('Recent conversations unavailable');
    }
    _rows
      ..clear()
      ..addEntries(
          result.rows.take(6).map((row) => MapEntry(row.conversationID, row)));
    return [
      for (final row in _rows.values)
        MediaShareRecipient(
            id: row.conversationID,
            name: row.showName ?? '',
            avatar: row.faceURL,
            isGroup: row.isGroupChat),
    ];
  }

  Future<void> stage(Message message, MediaShareRecipient recipient) async {
    final row = _rows[recipient.id];
    if (_staging ||
        !isCurrent() ||
        row == null ||
        !ContactSelectionPolicy.allows(row)) {
      return;
    }
    _staging = true;
    try {
      if (row.isGroupChat) {
        final joined = await OpenIM.iMManager.groupManager
            .isJoinedGroup(groupID: row.groupID!)
            .timeout(const Duration(seconds: 5));
        if (!isCurrent()) return;
        if (!joined) {
          IMViews.showToast('mediaMessageUnavailable'.tr);
          return;
        }
      }
      if (!isCurrent() || message.hasExpired) return;
      final staged = await AppNavigator.stageForward(
          PendingForward([message], row, merged: false),
          isCurrent: isCurrent);
      if (staged != true && isCurrent()) {
        IMViews.showToast('mediaMessageUnavailable'.tr);
      }
    } catch (_) {
      if (isCurrent()) IMViews.showToast(StrRes.sendFailed);
    } finally {
      _staging = false;
    }
  }
}
