import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Friend approval is a system message even on the approving (sender) side.
/// Keep its attention state separate from the SDK's incoming-message count.
class FriendApprovalNotice {
  FriendApprovalNotice({required this.read, required this.write});

  final Map? Function(String conversationID) read;
  final void Function(String conversationID, Map<String, dynamic> value) write;

  bool pending(ConversationInfo info) {
    final message = info.latestMsg;
    if (!info.isSingleChat ||
        message?.contentType !=
            MessageType.friendApplicationApprovedNotification ||
        message?.clientMsgID?.isNotEmpty != true) {
      return false;
    }
    final seen = read(info.conversationID);
    if (seen == null) return true;
    if (seen['id'] == message!.clientMsgID) return false;
    final sequence = message.seq ?? 0;
    final seenSequence = (seen['seq'] as num?)?.toInt() ?? 0;
    if (sequence > 0 && seenSequence > 0) return sequence > seenSequence;
    return (message.sendTime ?? info.latestMsgSendTime ?? 0) >=
        ((seen['time'] as num?)?.toInt() ?? 0);
  }

  /// Record successful reads even before the corresponding preview arrives.
  /// Older completions must not roll the watermark backwards.
  void confirm(String conversationID,
      {required String? messageID,
      required int? sequence,
      required int? time}) {
    if (messageID?.isNotEmpty != true) return;
    final previous = read(conversationID);
    final oldSequence = (previous?['seq'] as num?)?.toInt() ?? 0;
    final oldTime = (previous?['time'] as num?)?.toInt() ?? 0;
    if ((sequence ?? 0) > 0 && oldSequence > 0) {
      if (sequence! < oldSequence) return;
    } else if ((time ?? 0) < oldTime) {
      return;
    }
    write(conversationID,
        {'id': messageID, 'seq': sequence ?? 0, 'time': time ?? 0});
  }
}
