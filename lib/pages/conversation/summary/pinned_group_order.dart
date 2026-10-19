import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Account-local pin order. Missing rows may belong to an unloaded page.
class PinnedGroupOrder {
  PinnedGroupOrder(List<String> saved, {required this.save})
      : _ids = saved.toSet().toList();

  final List<String> _ids;
  final void Function(List<String>) save;

  List<ConversationInfo> apply(Iterable<ConversationInfo> rows) {
    final result = rows.toList();
    var changed = false;
    for (final row in result) {
      if (!row.isGroupChat) continue;
      if (row.isPinned == true) {
        if (!_ids.contains(row.conversationID)) {
          _ids.add(row.conversationID);
          changed = true;
        }
      } else {
        changed = _ids.remove(row.conversationID) || changed;
      }
    }
    if (changed) save(List.of(_ids));
    final rank = {for (var i = 0; i < _ids.length; i++) _ids[i]: i};
    final pinned = result
        .where((row) => row.isGroupChat && row.isPinned == true)
        .toList()
      ..sort(
          (a, b) => rank[a.conversationID]!.compareTo(rank[b.conversationID]!));
    var index = 0;
    for (var i = 0; i < result.length; i++) {
      if (result[i].isGroupChat && result[i].isPinned == true) {
        result[i] = pinned[index++];
      }
    }
    return result;
  }
}
