import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Keeps stale snapshots/events from recreating a conversation while its
/// delete-all request is in flight or after that deletion has completed.
class ConversationDeletionGuard {
  final _pending = <String, _DeleteRange>{};
  final _deleted = <String, ({int time, int draftTime, int? seq})>{};

  bool begin(ConversationInfo info) {
    if (_pending.containsKey(info.conversationID)) return false;
    _pending[info.conversationID] = _DeleteRange(info);
    return true;
  }

  void complete(String id) {
    final range = _pending.remove(id);
    if (range != null) {
      // Once deletion succeeds, keep only ordering evidence, never the
      // removed conversation's message body or media metadata.
      _deleted[id] =
          (time: range.time, draftTime: range.draftTime, seq: range.seq);
    }
  }

  ConversationInfo? fail(String id) => _pending.remove(id)?.lastEvent;

  bool allows(ConversationInfo info, {bool snapshot = false}) {
    final pending = _pending[info.conversationID];
    if (pending != null) {
      pending.observe(info, snapshot: snapshot);
      return false;
    }
    final removed = _deleted[info.conversationID];
    if (removed == null) return true;
    if (info.draftText?.isNotEmpty == true &&
        (info.draftTextTime ?? 0) > removed.draftTime) {
      _deleted.remove(info.conversationID);
      return true;
    }
    final time = info.latestMsgSendTime ?? 0;
    if (time < removed.time) return false;
    if (time == removed.time) {
      final seq = info.latestMsg?.seq;
      // A different message ID alone cannot prove it was sent after deletion.
      if (seq == null || removed.seq == null || seq <= removed.seq!) {
        return false;
      }
    }
    _deleted.remove(info.conversationID);
    return true;
  }

  void clear() {
    _pending.clear();
    _deleted.clear();
  }
}

class _DeleteRange {
  _DeleteRange(this.lastEvent) {
    observe(lastEvent);
  }
  ConversationInfo lastEvent;
  int time = 0;
  int draftTime = 0;
  int? seq;

  void observe(ConversationInfo info, {bool snapshot = false}) {
    final observedDraft = info.draftTextTime ?? 0;
    if (observedDraft > draftTime) draftTime = observedDraft;
    final observedTime = info.latestMsgSendTime ?? 0;
    final observedSeq = info.latestMsg?.seq;
    if (observedTime > time) {
      time = observedTime;
      seq = observedSeq;
    } else if (observedTime == time &&
        observedSeq != null &&
        (seq == null || observedSeq > seq!)) {
      seq = observedSeq;
    }
    if (!snapshot && observedTime >= (lastEvent.latestMsgSendTime ?? 0)) {
      lastEvent = info;
    }
  }
}
