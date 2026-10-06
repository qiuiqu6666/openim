import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'assistant_stream_chunk.dart';

/// Immutable presentation data. It is never inserted into the SDK timeline.
class AssistantStreamSnapshot {
  const AssistantStreamSnapshot({
    required this.streamID,
    required this.text,
    required this.ended,
  });

  final String streamID;
  final String text;
  final bool ended;
}

/// One route owns the deltas and completed IDs; dispose clears both.
/// Caller verifies sender, recipient and current account before accepting data.
class AssistantStreamState extends ChangeNotifier {
  final _streams = <String, _StreamBuffer>{};
  final _finalizedIDs = <String>{};
  bool _disposed = false;

  bool get isDisposed => _disposed;

  /// Map insertion order preserves the first arrival order of concurrent turns.
  List<AssistantStreamSnapshot> get snapshots =>
      List.unmodifiable(_streams.values.map((stream) => stream.snapshot));

  bool isFinalized(String streamID) => _finalizedIDs.contains(streamID);

  AssistantStreamSnapshot? accept(AssistantStreamChunk chunk) {
    if (_disposed ||
        chunk.streamID.trim().isEmpty ||
        chunk.index < 0 ||
        _finalizedIDs.contains(chunk.streamID)) {
      return null;
    }
    final existing = _streams[chunk.streamID];
    final stream = existing ?? _StreamBuffer(chunk.streamID);
    if (existing == null) _streams[chunk.streamID] = stream;
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
    final visible = _streams.isNotEmpty;
    _streams.clear();
    _finalizedIDs.clear();
    if (visible) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _streams.clear();
    _finalizedIDs.clear();
    super.dispose();
  }
}

class _StreamBuffer {
  _StreamBuffer(String streamID)
      : snapshot =
            AssistantStreamSnapshot(streamID: streamID, text: '', ended: false);

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
        streamID: snapshot.streamID, text: _text.toString(), ended: ended);
    return true;
  }
}
