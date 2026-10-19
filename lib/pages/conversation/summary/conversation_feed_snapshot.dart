import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';

import '../conversation_organizer.dart';
import '../unread/conversation_unread_count.dart';

/// Share one projection between the two feeds and their navigation badges.
class ConversationFeedSnapshotCache {
  ConversationFeedSnapshotCache(this.rows, this.states, {this.order}) {
    _workers = [
      ever(rows, (_) => _dirty = true),
      ever(states, (_) => _dirty = true),
    ];
  }
  final RxList<ConversationInfo> rows;
  final RxMap<String, ChatConversationState> states;
  final List<ConversationInfo> Function(Iterable<ConversationInfo>)? order;
  late final List<Worker> _workers;
  bool _dirty = true;
  ConversationFeedSnapshot? _snapshot;

  ConversationFeedSnapshot read() {
    // Register both dependencies even when the derived value is cached.
    rows.length;
    states.length;
    if (_dirty || _snapshot == null) {
      _snapshot = ConversationFeedSnapshot(order?.call(rows) ?? rows, states);
      _dirty = false;
    }
    return _snapshot!;
  }

  void dispose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    _snapshot = null;
  }
}

class ConversationFeedSnapshot {
  ConversationFeedSnapshot(Iterable<ConversationInfo> rows,
      Map<String, ChatConversationState> states) {
    for (final row in rows) {
      final state = states[row.conversationID];
      if (state?.archived == true) {
        if (row.isGroupChat) archivedGroups.add(row);
        if (row.isSingleChat) archivedSingles.add(row);
        continue;
      }
      final unread = notifiableConversationUnreadCount(row);
      if (row.isGroupChat) {
        groups.add(row);
        groupUnread += unread;
      }
      if (row.isSingleChat) {
        singles.add(row);
        singleUnread += unread;
      }
      final folder = state?.folderID;
      if (folder == null) continue;
      (folders[folder] ??= []).add(row);
      folderUnread.update(folder, (value) => value + row.unreadCount,
          ifAbsent: () => row.unreadCount);
      if (row.unreadCount > 0 && row.recvMsgOpt != 2) {
        notifiableFolders.add(folder);
      }
    }
  }

  final groups = <ConversationInfo>[];
  final singles = <ConversationInfo>[];
  final archivedGroups = <ConversationInfo>[];
  final archivedSingles = <ConversationInfo>[];
  final folders = <String, List<ConversationInfo>>{};
  final folderUnread = <String, int>{};
  final notifiableFolders = <String>{};
  int groupUnread = 0;
  int singleUnread = 0;
}
