import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'assistant_stream_chunk.dart';

/// Immutable presentation data. It is never inserted into the SDK timeline.
class AssistantStreamSnapshot {
  const AssistantStreamSnapshot({
    required this.streamID,
    required this.text,
    required this.ended,
    this.waiting = false,
    this.rowID,
  });

  final String streamID;
  final String text;
  final bool ended;
  final bool waiting;
  final String? rowID;
  String get presentationID => rowID ?? streamID;
}

/// One route owns the deltas and completed IDs; dispose clears both.
/// Caller verifies sender, recipient and current account before accepting data.
class AssistantStreamState extends ChangeNotifier {
  final _streams = <String, _StreamBuffer>{};
  final _finalizedIDs = <String>{};
  _ReplyWait? _replyWait;
  int _nextReplyToken = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Map insertion order preserves the first arrival order of concurrent turns.
  List<AssistantStreamSnapshot> get snapshots => List.unmodifiable([
        ..._streams.values.map((stream) => stream.snapshot),
        if (_replyWait case final wait?) wait.snapshot,
      ]);

  /// Sending again shares the visible placeholder, but owns a separate failure.
  int? beginReply() {
    if (_disposed) return null;
    final token = ++_nextReplyToken;
    final fresh = _replyWait == null;
    final wait = _replyWait ??= _ReplyWait(token);
    wait.tokens.add(token);
    if (fresh) notifyListeners();
    return token;
  }

  void cancelReply(int? token) {
    if (_disposed || token == null) return;
    final wait = _replyWait;
    if (wait == null || !wait.tokens.remove(token) || wait.tokens.isNotEmpty) {
      return;
    }
    _replyWait = null;
    notifyListeners();
  }

  /// Only live, account-validated replies complete a new local wait. History
  /// reconciliation continues to use markFinalMessage without consuming it.
  void receivedReply(Message message) {
    if (_disposed ||
        message.contentType == MessageType.typing ||
        AssistantStreamChunk.isStreamMessage(message)) {
      return;
    }
    final id = AssistantStreamChunk.finalStreamID(message);
    final known =
        id != null && (_streams.containsKey(id) || _finalizedIDs.contains(id));
    var waitingRemoved = !known && _replyWait != null;
    if (waitingRemoved) _replyWait = null;
    // Some normal text/image replies have no stream ID. An earlier empty
    // fragment may already have adopted the local wait; retire only those
    // empty waiting rows, leaving visible text from other turns intact.
    if (id == null) {
      final emptyWaits = _streams.entries
          .where((entry) =>
              entry.value.snapshot.waiting && entry.value.snapshot.text.isEmpty)
          .map((entry) => entry.key)
          .toList();
      for (final streamID in emptyWaits) {
        _streams.remove(streamID);
        _finalizedIDs.add(streamID);
      }
      waitingRemoved |= emptyWaits.isNotEmpty;
    }
    final streamRemoved = markFinalMessage(message);
    if (waitingRemoved && !streamRemoved) notifyListeners();
  }

  bool isFinalized(String streamID) => _finalizedIDs.contains(streamID);

  AssistantStreamSnapshot? accept(AssistantStreamChunk chunk) {
    if (_disposed ||
        chunk.streamID.trim().isEmpty ||
        chunk.index < 0 ||
        _finalizedIDs.contains(chunk.streamID)) {
      return null;
    }
    final existing = _streams[chunk.streamID];
    final wait = existing == null ? _replyWait : null;
    final stream = existing ??
        _StreamBuffer(chunk.streamID,
            rowID: wait?.snapshot.presentationID, waiting: wait != null);
    if (existing == null) {
      _streams[chunk.streamID] = stream;
      if (wait != null) _replyWait = null;
    }
    final changed = stream.accept(chunk);
    if (!changed && existing != null) return null;
    notifyListeners();
    return stream.snapshot;
  }

  /// The final ordinary message replaces any transient stream with this ID.
  /// Remember its ID even if the final message arrived before the first delta.
  bool markFinal(String streamID) {
    if (_disposed || streamID.trim().isEmpty) return false;
    _finalizedIDs.add(streamID);
    final removed = _streams.remove(streamID) != null;
    if (removed) notifyListeners();
    return removed;
  }

  bool markFinalMessage(Message message) {
    final id = AssistantStreamChunk.finalStreamID(message);
    return id != null && markFinal(id);
  }

  void clear() {
    if (_disposed) return;
    final visible = _streams.isNotEmpty || _replyWait != null;
    _streams.clear();
    _finalizedIDs.clear();
    _replyWait = null;
    if (visible) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _streams.clear();
    _finalizedIDs.clear();
    _replyWait = null;
    super.dispose();
  }
}

class _ReplyWait {
  _ReplyWait(int token)
      : snapshot = AssistantStreamSnapshot(
            streamID: 'assistant-wait:$token',
            rowID: 'assistant-wait:$token',
            text: '',
            ended: false,
            waiting: true);

  final AssistantStreamSnapshot snapshot;
  final tokens = <int>{};
}

class _StreamBuffer {
  _StreamBuffer(String streamID, {String? rowID, bool waiting = false})
      : snapshot = AssistantStreamSnapshot(
            streamID: streamID,
            text: '',
            ended: false,
            rowID: rowID,
            waiting: waiting);

  AssistantStreamSnapshot snapshot;
  final _pending = <int, AssistantStreamChunk>{};
  final _text = StringBuffer();
  int _nextIndex = 0;
  int? _endIndex;

  bool accept(AssistantStreamChunk chunk) {
    if (snapshot.ended ||
        chunk.index < _nextIndex ||
        _pending.containsKey(chunk.index) ||
        (_endIndex != null && chunk.index > _endIndex!)) {
      return false;
    }
    if (chunk.end) {
      _endIndex = chunk.index;
      _pending.removeWhere((index, _) => index > chunk.index);
    }
    _pending[chunk.index] = chunk;
    var ended = false;
    var appended = false;
    while (_pending.containsKey(_nextIndex)) {
      final next = _pending.remove(_nextIndex)!;
      _text.write(next.text);
      appended |= next.text.isNotEmpty;
      _nextIndex++;
      if (next.end) {
        ended = true;
        _pending.clear();
        break;
      }
    }
    if (!appended && !ended) return false;
    snapshot = AssistantStreamSnapshot(
        streamID: snapshot.streamID,
        text: _text.toString(),
        ended: ended,
        rowID: snapshot.rowID,
        waiting: snapshot.waiting && _text.isEmpty);
    return true;
  }
}
