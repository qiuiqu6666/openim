import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Menu eligibility and execution checks share the same role hierarchy.
class ChatRevocationPolicy {
  ChatRevocationPolicy._();

  static bool canRevoke({
    required Message message,
    required String currentUserID,
    required int nowMilliseconds,
    String? groupID,
    bool isJoined = false,
    GroupInfo? group,
    int? selfRole,
    int? senderRole,
  }) {
    final type = message.contentType;
    if (currentUserID.isEmpty ||
        message.clientMsgID?.trim().isNotEmpty != true ||
        message.sendID?.trim().isNotEmpty != true ||
        message.status != MessageStatus.succeeded ||
        type == null ||
        type <= 0 ||
        type >= 1000 ||
        type == MessageType.typing ||
        message.hasExpired ||
        (type == MessageType.custom &&
            FundMessageData.tryParse(message.customElem?.data) != null)) {
      return false;
    }
    final inGroup = groupID?.isNotEmpty == true;
    if (inGroup &&
        (!isJoined ||
            !message.isGroupChat ||
            message.groupID != groupID ||
            group?.status == 1 ||
            group?.status == 2)) {
      return false;
    }
    if (!inGroup && !message.isSingleChat) return false;

    if (message.sendID == currentUserID) {
      final sentAt = message.sendTime;
      return sentAt != null &&
          sentAt > 0 &&
          nowMilliseconds - sentAt < const Duration(minutes: 2).inMilliseconds;
    }

    if (!inGroup ||
        group?.groupID != groupID ||
        message.sendID == group?.ownerUserID) {
      return false;
    }
    if (selfRole == GroupRoleLevel.owner) {
      if (group?.ownerUserID != currentUserID) return false;
      return senderRole == GroupRoleLevel.member ||
          senderRole == GroupRoleLevel.admin;
    }
    return selfRole == GroupRoleLevel.admin &&
        senderRole == GroupRoleLevel.member;
  }
}
