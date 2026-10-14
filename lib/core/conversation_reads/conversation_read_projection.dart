import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'conversation_read_request.dart';

/// Keeps successful read targets across late SDK events and list snapshots.
/// Only a reconciled SDK zero can clear an increased count for the same target.
class ConversationReadProjection {
  static const _conversationLimit = 256;
  static const _targetsPerConversation = 8;
  final _confirmed = <String, List<ConversationReadRequest>>{};
  final _reconcileZeros = <String, (String?, int?, int?, int)>{};

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
      final oldest = _confirmed.keys.first;
      _confirmed.remove(oldest);
      _reconcileZeros.remove(oldest);
    }
  }

  ConversationInfo project(ConversationInfo incoming,
      {ConversationInfo? current, bool authoritativeUnread = false}) {
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
            ? current.unreadCount > covering.unreadCount &&
                !(authoritativeUnread && incoming.unreadCount == 0)
            : !covering.followsPreview(current) &&
                _mayBeNewer(current, incoming))) {
      return current;
    }
    if (authoritativeUnread &&
        incoming.unreadCount == 0 &&
        current != null &&
        _sameTarget(current, incoming) &&
        current.unreadCount > covering.unreadCount) {
      // The fresh SDK query has reconciled this larger same-message count.
      // Remember it too, otherwise the next buffered copy resurrects the badge.
      confirm(ConversationReadRequest.capture(current));
    }
    incoming.unreadCount = 0;
    _reconcileZeros.remove(incoming.conversationID);
    return incoming;
  }

  /// A rejected same-target zero needs a fresh SDK query, once per protected
  /// state. SDK callbacks emitted by that query cannot create a repair loop.
  bool takeReconciliationSignal(
      ConversationInfo incoming, ConversationInfo projected) {
    if (!_confirmed.containsKey(incoming.conversationID) ||
        incoming.unreadCount != 0 ||
        projected.unreadCount <= 0 ||
        !_sameTarget(incoming, projected)) {
      return false;
    }
    final snapshot = (
      projected.latestMsg?.clientMsgID,
      projected.latestMsg?.seq,
      projected.latestMsgSendTime,
      projected.unreadCount
    );
    if (_reconcileZeros[incoming.conversationID] == snapshot) return false;
    _reconcileZeros[incoming.conversationID] = snapshot;
    return true;
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

  void clear() {
    _confirmed.clear();
    _reconcileZeros.clear();
  }
}
