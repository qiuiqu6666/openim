import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'conversation_read_request.dart';

/// Keeps successful read targets across late SDK events and list snapshots.
/// It never acknowledges a different message or an increased unread count.
class ConversationReadProjection {
  static const _conversationLimit = 256;
  static const _targetsPerConversation = 8;
  final _confirmed = <String, List<ConversationReadRequest>>{};

  void confirm(ConversationReadRequest request) {
    if (!request.hasTarget) return;
    final targets = _confirmed.remove(request.conversationID) ?? [];
    final matching = targets
        .where((target) =>
            target.latestMsgSendTime == request.latestMsgSendTime &&
            target.messageID == request.messageID &&
            target.messageSequence == request.messageSequence)
        .toList();
    final strongest =
        matching.isNotEmpty && matching.first.unreadCount >= request.unreadCount
            ? matching.first
            : request;
    targets.removeWhere(matching.contains);
    targets.add(strongest);
    if (targets.length > _targetsPerConversation) targets.removeAt(0);
    _confirmed[request.conversationID] = targets;
    if (_confirmed.length > _conversationLimit) {
      _confirmed.remove(_confirmed.keys.first);
    }
  }

  ConversationInfo project(ConversationInfo incoming,
      {ConversationInfo? current}) {
    final targets = _confirmed[incoming.conversationID];
    if (targets == null) return incoming;
    ConversationReadRequest? covering;
    for (final target in targets) {
      if (current != null &&
          target.matchesTarget(current) &&
          target.followsPreview(incoming)) {
        return current;
      }
      if (target.canClear(incoming)) covering = target;
    }
    if (covering == null) return incoming;
    // A delayed snapshot of an acknowledged message must not replace a later
    // message already shown by the list, including distinct same-time IDs.
    if (current != null &&
        (_sameTarget(current, incoming)
            ? current.unreadCount > covering.unreadCount
            : !covering.followsPreview(current) &&
                _mayBeNewer(current, incoming))) {
      return current;
    }
    incoming.unreadCount = 0;
    return incoming;
  }

  bool _sameTarget(ConversationInfo first, ConversationInfo second) =>
      first.latestMsgSendTime == second.latestMsgSendTime &&
      first.latestMsg?.clientMsgID == second.latestMsg?.clientMsgID &&
      first.latestMsg?.seq == second.latestMsg?.seq;

  bool _mayBeNewer(ConversationInfo current, ConversationInfo incoming) {
    final currentSeq = current.latestMsg?.seq ?? 0;
    final incomingSeq = incoming.latestMsg?.seq ?? 0;
    if (currentSeq > 0 && incomingSeq > 0) return currentSeq > incomingSeq;
    final currentTime = current.latestMsgSendTime ?? 0;
    final incomingTime = incoming.latestMsgSendTime ?? 0;
    if (currentTime != incomingTime) return currentTime > incomingTime;
    // Unknown sequences cannot order distinct messages sent at the same time.
    return true;
  }

  void clear() => _confirmed.clear();
}
