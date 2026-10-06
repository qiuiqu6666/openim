import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Captures the exact conversation target before its native read is sent.
/// Completion reports the SDK outcome without retaining a mutable SDK model.
class ConversationReadRequest {
  ConversationReadRequest.capture(ConversationInfo info,
      {Message? visibleLatestMessage, int knownUnreadCount = 0})
      : conversationID = info.conversationID,
        latestMsgSendTime = visibleLatestMessage == null
            ? info.latestMsgSendTime
            : visibleLatestMessage.sendTime ?? info.latestMsgSendTime,
        messageID = (visibleLatestMessage ?? info.latestMsg)?.clientMsgID,
        messageSequence = (visibleLatestMessage ?? info.latestMsg)?.seq,
        unreadCount = info.unreadCount > knownUnreadCount
            ? info.unreadCount
            : knownUnreadCount,
        _previewMessageID = info.latestMsg?.clientMsgID,
        _previewSequence = info.latestMsg?.seq,
        _previewTime = info.latestMsgSendTime,
        _previewUnreadCount = info.unreadCount;

  final String conversationID;
  final int? latestMsgSendTime;
  final String? messageID;
  final int? messageSequence;
  final int unreadCount;
  final String? _previewMessageID;
  final int? _previewSequence;
  final int? _previewTime;
  final int _previewUnreadCount;
  final _completion = Completer<bool>();

  Future<bool> get result => _completion.future;

  void complete(bool succeeded) {
    if (!_completion.isCompleted) _completion.complete(succeeded);
  }

  bool matchesTarget(ConversationInfo info) =>
      conversationID == info.conversationID &&
      latestMsgSendTime == info.latestMsgSendTime &&
      messageID == info.latestMsg?.clientMsgID &&
      messageSequence == info.latestMsg?.seq;

  bool canClear(ConversationInfo info) =>
      matchesTarget(info) && info.unreadCount <= unreadCount;

  /// A painted target can arrive before its conversation preview. This exact
  /// previous preview is known to precede the target even with an unknown seq.
  bool followsPreview(ConversationInfo info) =>
      _previewMessageID?.isNotEmpty == true &&
      messageID != _previewMessageID &&
      info.conversationID == conversationID &&
      info.latestMsg?.clientMsgID == _previewMessageID &&
      info.latestMsg?.seq == _previewSequence &&
      info.latestMsgSendTime == _previewTime &&
      info.unreadCount <= _previewUnreadCount;

  bool get hasTarget =>
      messageID?.isNotEmpty == true ||
      (messageSequence ?? 0) > 0 ||
      (latestMsgSendTime ?? 0) > 0;
}
