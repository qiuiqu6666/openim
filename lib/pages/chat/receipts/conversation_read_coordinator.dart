import '../messages/identity/message_sequence_history.dart';

/// Coalesces conversation reads while preserving messages arriving mid-request.
class ConversationReadCoordinator {
  Future<void>? _pending;
  int _readThrough = -1;
  int _readRevision = -1;
  final _readMessageIDs = MessageSequenceHistory();

  Future<void> markRead(int sequence, Future<void> Function() send,
      {String? messageID, int? identitySequence, int revision = 0}) async {
    final hasIdentity = messageID != null && messageID.isNotEmpty;
    final covered = sequence > 0 || hasIdentity;
    if (covered &&
        sequence <= _readThrough &&
        (!hasIdentity ||
            _readMessageIDs.contains(messageID, identitySequence)) &&
        revision <= _readRevision) {
      return;
    }
    final pending = _pending;
    if (pending != null) {
      await pending;
      await markRead(sequence, send,
          messageID: messageID,
          identitySequence: identitySequence,
          revision: revision);
      return;
    }
    final request = Future<void>.sync(send);
    _pending = request;
    try {
      await request;
      if (sequence > _readThrough) _readThrough = sequence;
      if (revision > _readRevision) _readRevision = revision;
      if (hasIdentity) _readMessageIDs.add(messageID, identitySequence);
    } finally {
      _pending = null;
    }
  }
}
