import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../../core/conversation_reads/conversation_batch_read_api.dart';

/// A route-entry snapshot, never a live preview read at retry/exit time.
class ChatEntryRead {
  ChatEntryRead.capture(ConversationInfo info,
      {required bool historyEntry, required String accountID})
      : target = _capture(info, historyEntry, accountID);
  final BatchReadTarget? target;
  bool _sent = false;

  void enter(
      {required bool active, required void Function(BatchReadTarget) send}) {
    if (!active || _sent || target == null) return;
    _sent = true;
    send(target!);
  }

  static BatchReadTarget? _capture(
      ConversationInfo info, bool history, String self) {
    final message = info.latestMsg;
    if (history ||
        self.isEmpty ||
        info.isPrivateChat == true ||
        message == null ||
        message.attachedInfoElem?.isPrivateChat == true ||
        message.status != MessageStatus.succeeded ||
        (message.seq ?? 0) <= 0 ||
        message.clientMsgID?.isNotEmpty != true) {
      return null;
    }
    final members = [self, info.userID ?? '']..sort();
    final single = info.conversationType == ConversationType.single &&
        message.sessionType == ConversationType.single &&
        info.userID?.isNotEmpty == true &&
        info.conversationID == 'si_${members.join('_')}' &&
        ((message.sendID == self && message.recvID == info.userID) ||
            (message.sendID == info.userID && message.recvID == self));
    final group = info.conversationType == ConversationType.superGroup &&
        message.sessionType == ConversationType.superGroup &&
        info.groupID?.isNotEmpty == true &&
        message.groupID == info.groupID &&
        info.conversationID == 'sg_${info.groupID}';
    if (!single && !group) return null;
    return BatchReadTarget(info.conversationID, message.seq!);
  }
}
