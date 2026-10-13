import 'package:flutter/widgets.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Owns only the current feed's structure, never mutable conversation payloads.
class ConversationRowIndices {
  List<String> _ids = const [];
  int _offset = -1;
  Map<Key, int> _indices = const {};

  Map<Key, int> read(List<ConversationInfo> rows, {required int offset}) {
    if (_offset == offset && _ids.length == rows.length) {
      var unchanged = true;
      for (var i = 0; i < rows.length; i++) {
        if (_ids[i] != rows[i].conversationID) {
          unchanged = false;
          break;
        }
      }
      if (unchanged) return _indices;
    }
    _offset = offset;
    _ids = [for (final row in rows) row.conversationID];
    return _indices = Map.unmodifiable({
      for (var i = 0; i < _ids.length; i++)
        ValueKey('slide-scope-${_ids[i]}'): i + offset,
    });
  }
}
