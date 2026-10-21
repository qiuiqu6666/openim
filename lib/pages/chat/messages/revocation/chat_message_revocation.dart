import 'package:openim_common/localization.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../group/member_actions/chat_member_action_sources.dart';
import 'chat_revocation_policy.dart';
import 'chat_revocation_trace.dart';

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
    this.confirm,
    this.log,
    RevokeMemberReader? readMembers,
    RevokeMessageRequest? revoke,
    int Function()? nowMilliseconds,
  })  : _readMembers = readMembers ?? ChatMemberActionSources.sdk().read,
        _revoke = revoke,
        _nowMilliseconds = nowMilliseconds ?? _systemNow;

  final String Function() conversationID, currentUserID;
  final String? Function() groupID;
  final GroupInfo? Function() groupInfo;
  final int? Function(String userID) memberRole;
  final bool Function() isJoined, isClosed;
  final int Function() groupRevision;
  final bool Function(Message) isCurrentMessage;
  final void Function(String) onRevoked, showFeedback;
  final Future<bool> Function(Message message)? confirm;
  final RevocationLog? log;
  bool _confirming = false;
  final RevokeMemberReader _readMembers;
  final RevokeMessageRequest? _revoke;
  final int Function() _nowMilliseconds;
  final _pending = <String>{};

  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;
  static Future<void> _sdkRevoke({
    required String conversationID,
    required String clientMsgID,
    required String operationID,
  }) async {
    await OpenIM.iMManager.messageManager.revokeMessage(
        conversationID: conversationID,
        clientMsgID: clientMsgID,
        operationID: operationID);
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
    final trace = ChatRevocationTrace(
      accountID: currentUserID(),
      conversationID: conversationID(),
      clientMsgID: message.clientMsgID,
      seq: message.seq,
      log: log,
    )..record('click');
    void stop(String reason, [String? feedback]) {
      trace.record('stopped', outcome: reason);
      if (feedback != null && !isClosed()) showFeedback(feedback);
    }

    String unavailable() {
      if (!isCurrentMessage(message)) return AppCopy.text('消息状态已变化，请重新长按消息');
      if (message.sendID == currentUserID() &&
          (message.sendTime ?? 0) > 0 &&
          _nowMilliseconds() - message.sendTime! >=
              const Duration(minutes: 2).inMilliseconds) {
        return AppCopy.text('消息已超过两分钟，无法撤回');
      }
      return AppCopy.text('当前消息无法撤回或你没有撤回权限');
    }

    void reject() {
      final feedback = unavailable();
      stop(
          feedback == '消息已超过两分钟，无法撤回'
              ? 'time_limit_exceeded'
              : !isCurrentMessage(message)
                  ? 'message_changed'
                  : 'permission_or_message_invalid',
          feedback);
    }

    if (isClosed()) {
      stop('session_closed');
      return;
    }
    if (_confirming) {
      stop('confirmation_pending', AppCopy.text('请先完成当前撤回确认'));
      return;
    }
    if (!canRevoke(message)) {
      reject();
      return;
    }
    final id = message.clientMsgID!;
    if (!_pending.add(id)) {
      stop('request_pending', AppCopy.text('正在撤回，请稍候'));
      return;
    }
    final account = currentUserID();
    final conversation = conversationID();
    final group = groupID();
    bool current() =>
        !isClosed() &&
        currentUserID() == account &&
        conversationID() == conversation &&
        groupID() == group;
    bool validate() {
      if (!current()) {
        stop('session_changed');
        return false;
      }
      if (!canRevoke(message)) {
        reject();
        return false;
      }
      return true;
    }

    var stage = 'validation';
    try {
      if (confirm != null) {
        stage = 'confirmation';
        trace.record('confirmation', outcome: 'shown');
        _confirming = true;
        final bool confirmed;
        try {
          confirmed = await confirm!(message);
        } finally {
          _confirming = false;
        }
        trace.record('confirmation',
            outcome: confirmed ? 'accepted' : 'cancelled');
        if (!confirmed) return;
        if (!validate()) return;
      } else {
        trace.record('confirmation', outcome: 'not_required');
      }
      if (message.sendID != account) {
        stage = 'permission_check';
        trace.record(stage, outcome: 'started');
        final revision = groupRevision();
        final snapshot = await _readMembers(group!, account, message.sendID!);
        if (!validate()) return;
        if (revision != groupRevision()) {
          stop('membership_changed', AppCopy.text('群成员信息已变化，请重新长按消息'));
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
          stop('permission_denied', AppCopy.text('当前消息无法撤回或你没有撤回权限'));
          return;
        }
      }
      if (!validate()) return;
      stage = 'sdk_call';
      trace.record(stage, outcome: 'started');
      if (_revoke case final revoke?) {
        await revoke(conversationID: conversation, clientMsgID: id);
      } else {
        await _sdkRevoke(
            conversationID: conversation,
            clientMsgID: id,
            operationID: trace.id);
      }
      // SDK failures may precede HTTP dispatch; this is not an HTTP receipt.
      trace.record('request_result', outcome: 'sdk_success');
      stage = 'local_update';
      // A role change after dispatch does not undo an accepted server result.
      if (current()) {
        onRevoked(id);
      } else {
        stop('session_changed_after_success');
      }
    } catch (error) {
      trace.record(stage == 'sdk_call' ? 'request_result' : stage,
          outcome: stage == 'sdk_call' ? 'sdk_failed' : 'failed', error: error);
      if (!current()) {
        stop('session_changed');
        return;
      }
      if (stage == 'confirmation') {
        showFeedback(AppCopy.text('无法打开撤回确认，请重新长按消息重试'));
        return;
      }
      if (stage == 'local_update') {
        showFeedback(AppCopy.text('撤回已成功，显示更新失败，请重新进入聊天核对'));
        return;
      }
      showFeedback(error is PlatformException &&
              int.tryParse(error.code) == SDKErrorCode.insufficientPermissions
          ? AppCopy.text('你没有撤回这条消息的权限')
          : AppCopy.text('撤回失败，请检查网络或消息是否已超过可撤回时限'));
    } finally {
      _pending.remove(id);
    }
  }
}
