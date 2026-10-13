import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Optional search-source capability. SDK history retrieval fills its local DB.
abstract interface class ChatHistoryCloudSource {
  bool get cloudHasMore;
  Future<void> supplement(String conversationID, bool Function() isCurrent);
}

typedef HistoryPageFetcher = Future<AdvancedMessage> Function(
    String conversationID, Message? cursor, int count);

class ChatHistoryCloudSync {
  ChatHistoryCloudSync(this.fetch);
  final HistoryPageFetcher fetch;
  Message? _cursor;
  String? _conversationID;
  bool hasMore = true;
  Future<void>? _pending;

  Future<void> load(String id, bool Function() isCurrent) async {
    if (id.trim().isEmpty) throw ArgumentError('Conversation ID required');
    // A replacement query waits for the old native request to finish rather
    // than issuing overlapping requests against the same cursor.
    final pending = _pending;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    if (!isCurrent() || !hasMore) return;
    if (_conversationID != null && _conversationID != id) {
      throw StateError('History synchronization conversation changed');
    }
    _conversationID = id;
    final task = _load(id, isCurrent);
    _pending = task;
    try {
      await task;
    } finally {
      if (identical(_pending, task)) _pending = null;
    }
  }

  Future<void> _load(String id, bool Function() isCurrent) async {
    final page =
        await fetch(id, _cursor, 100).timeout(const Duration(seconds: 30));
    if (!isCurrent()) return;
    if (page.errCode != null && page.errCode != 0) {
      throw StateError('History synchronization failed: ${page.errCode}');
    }
    final messages = page.messageList ?? <Message>[];
    if (messages.isEmpty) {
      if (page.isEnd != true) {
        throw StateError('History cursor did not advance');
      }
      hasMore = false;
      return;
    }
    // The SDK returns history oldest first; its first message is the cursor.
    final oldest = messages.first;
    if (oldest.clientMsgID?.isNotEmpty != true ||
        oldest.clientMsgID == _cursor?.clientMsgID) {
      if (page.isEnd == true) {
        hasMore = false;
        return;
      }
      throw StateError('History cursor did not advance');
    }
    _cursor = oldest;
    hasMore = page.isEnd != true;
  }
}
