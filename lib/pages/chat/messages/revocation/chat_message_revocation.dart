import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../group/member_actions/chat_member_action_sources.dart';
import 'chat_revocation_policy.dart';

typedef RevokeMessageRequest = Future<void> Function({
  required String conversationID,
  required String clientMsgID,
});
typedef RevokeMemberReader = Future<ChatMemberActionSnapshot> Function(
    String groupID, String selfID, String senderID);

/// One chat's recall operation. Existing SDK events/history own synchronization.
class ChatMessageRevocation {
  ChatMessageRevocation({
    required this.conversationID,
    required this.currentUserID,
    required this.groupID,
    required this.groupInfo,
    required this.memberRole,
    required this.isJoined,
    required this.groupRevision,
    required this.isCurrentMessage,
    required this.isClosed,
    required this.onRevoked,
    required this.showFeedback,
    RevokeMemberReader? readMembers,
    RevokeMessageRequest? revoke,
    int Function()? nowMilliseconds,
  })  : _readMembers = readMembers ?? ChatMemberActionSources.sdk().read,
        _revoke = revoke ?? _sdkRevoke,
        _nowMilliseconds = nowMilliseconds ?? _systemNow;

  final String Function() conversationID, currentUserID;
  final String? Function() groupID;
  final GroupInfo? Function() groupInfo;
  final int? Function(String userID) memberRole;
  final bool Function() isJoined, isClosed;
  final int Function() groupRevision;
  final bool Function(Message) isCurrentMessage;
  final void Function(String) onRevoked, showFeedback;
  final RevokeMemberReader _readMembers;
  final RevokeMessageRequest _revoke;
  final int Function() _nowMilliseconds;
  final _pending = <String>{};

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;
  static Future<void> _sdkRevoke({
    required String conversationID,
    required String clientMsgID,
  }) async {
    await OpenIM.iMManager.messageManager.revokeMessage(
        conversationID: conversationID, clientMsgID: clientMsgID);
  }

  bool canRevoke(Message message) =>
      !isClosed() &&
      isCurrentMessage(message) &&
      ChatRevocationPolicy.canRevoke(
        message: message,
        currentUserID: currentUserID(),
        nowMilliseconds: _nowMilliseconds(),
        groupID: groupID(),
        isJoined: isJoined(),
        group: groupInfo(),
        selfRole: memberRole(currentUserID()),
        senderRole: memberRole(message.sendID ?? ''),
      );

  Future<void> revokeMessage(Message message) async {
    if (isClosed() || !isCurrentMessage(message)) return;
    if (!canRevoke(message)) {
      showFeedback('当前消息无法撤回或你没有撤回权限');
      return;
    }
    final id = message.clientMsgID!;
    if (!_pending.add(id)) return;
    final account = currentUserID();
    final conversation = conversationID();
    final group = groupID();
    bool current() =>
        !isClosed() &&
        currentUserID() == account &&
        conversationID() == conversation &&
        groupID() == group;
    try {
      if (message.sendID != account) {
        final revision = groupRevision();
        final snapshot = await _readMembers(group!, account, message.sendID!);
        if (!current() || !isCurrentMessage(message)) return;
        if (revision != groupRevision()) {
          showFeedback('群成员信息已变化，请重新长按消息');
          return;
        }
        if (snapshot.self?.groupID != group ||
            snapshot.self?.userID != account ||
            (snapshot.target != null &&
                (snapshot.target?.groupID != group ||
                    snapshot.target?.userID != message.sendID)) ||
            !ChatRevocationPolicy.canRevoke(
              message: message,
              currentUserID: account,
              nowMilliseconds: _nowMilliseconds(),
              groupID: group,
              isJoined: snapshot.isJoined,
              group: snapshot.group,
              selfRole: snapshot.self?.roleLevel,
              senderRole: snapshot.target?.roleLevel,
            )) {
          showFeedback('当前消息无法撤回或你没有撤回权限');
          return;
        }
      }
      if (!current() || !canRevoke(message)) return;
      await _revoke(conversationID: conversation, clientMsgID: id);
      // A role change after dispatch does not undo an accepted server result.
      if (current()) onRevoked(id);
    } catch (error) {
      if (!current()) return;
      Logger.print('Revoke message failed: $error');
      showFeedback(error is PlatformException &&
              int.tryParse(error.code) == SDKErrorCode.insufficientPermissions
          ? '你没有撤回这条消息的权限'
          : '撤回失败，请检查网络或消息是否已超过可撤回时限');
    } finally {
      _pending.remove(id);
    }
  }
}
