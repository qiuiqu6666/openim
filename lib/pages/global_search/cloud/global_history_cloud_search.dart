import 'dart:collection';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../chat/history_search/cloud/chat_history_cloud_sync.dart';

typedef ConversationPage = Future<List<ConversationInfo>> Function(int offset);

/// Bounded, round-robin hydration across the signed-in account's conversations.
class GlobalHistoryCloudSearch {
  GlobalHistoryCloudSearch(
      {ConversationPage? conversations, HistoryPageFetcher? history})
      : _conversations = conversations ??
            ((offset) => OpenIM.iMManager.conversationManager
                .getConversationListSplit(offset: offset, count: 50)),
        _history = history ??
            ((id, cursor, count) => OpenIM.iMManager.messageManager
                .getAdvancedHistoryMessageList(
                    conversationID: id, startMsg: cursor, count: count));

  final ConversationPage _conversations;
  final HistoryPageFetcher _history;
  final _queue = Queue<String>();
  final _histories = <String, ChatHistoryCloudSync>{};
  int _offset = 0;
  bool _listed = false;
  bool get hasMore => !_listed || _queue.isNotEmpty;

  Future<void> supplement(bool Function() current) async {
    if (!current()) return;
    // Discover another bounded page before cycling existing history. Chats
    // absent from the home list's rendered window must also be searched.
    if (!_listed) {
      final page =
          await _conversations(_offset).timeout(const Duration(seconds: 30));
      if (!current()) return;
      var added = 0;
      for (final conversation in page) {
        final id = conversation.conversationID;
        if (id.isEmpty || _histories.containsKey(id)) continue;
        _histories[id] = ChatHistoryCloudSync(_history);
        _queue.add(id);
        added++;
      }
      if (page.length >= 50 && added == 0) {
        throw StateError('Conversation cursor did not advance');
      }
      _offset += page.length;
      _listed = page.length < 50;
    }
    final batchSize = _queue.length < 3 ? _queue.length : 3;
    for (var index = 0; index < batchSize && current(); index++) {
      final id = _queue.first;
      final history = _histories[id]!;
      await history.load(id, current);
      if (!current()) return;
      _queue.removeFirst();
      if (history.hasMore) _queue.addLast(id);
    }
  }
}
