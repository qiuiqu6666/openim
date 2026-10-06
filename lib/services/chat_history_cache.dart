import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Small, process-local first-page snapshots, isolated by signed-in IM account.
/// Private/expiring messages are always obtained afresh from the SDK.
class ChatHistoryCache {
  static const _maxConversations = 12;
  static const _maxMessages = 40;
  static final _entries = <(String, String), List<Message>>{};
  static final _removedMessages = <(String, String)>{};
  static int _epoch = 0;
  static int _nextRevision = 0;
  static int _revisionFloor = 0;
  static bool _latestSeedSafe = true;
  static final _conversationRevisions = <(String, String), int>{};
  static int get epoch => _epoch;
  static bool get canSeedLatest => _latestSeedSafe;

  static int revision(String accountID, String conversationID) =>
      _conversationRevisions[(accountID, conversationID)] ?? _revisionFloor;

  static bool isRemoved(String accountID, String? messageID) =>
      messageID != null && _removedMessages.contains((accountID, messageID));

  static List<Message> read(String accountID, String conversationID) {
    final key = (accountID, conversationID);
    final cached = _entries.remove(key);
    if (cached == null) return [];
    // A send completion can mark a cached object's attached info private.
    cached.removeWhere((m) =>
        m.attachedInfoElem?.isPrivateChat == true ||
        isRemoved(accountID, m.clientMsgID));
    if (cached.isNotEmpty) _entries[key] = cached;
    return List<Message>.of(cached);
  }

  static void write(
      String accountID, String conversationID, List<Message> messages,
      {int? epoch}) {
    if (epoch != null && epoch != _epoch) return;
    if (accountID.isEmpty || conversationID.isEmpty) return;
    final key = (accountID, conversationID);
    _entries.remove(key);
    // Only the contiguous latest page is cached: filtering private items must
    // not pull older messages forward and change first-page chronology.
    final start =
        messages.length > _maxMessages ? messages.length - _maxMessages : 0;
    final safe = messages
        .skip(start)
        .where((m) =>
            m.clientMsgID?.isNotEmpty == true &&
            !isRemoved(accountID, m.clientMsgID) &&
            m.attachedInfoElem?.isPrivateChat != true &&
            m.contentType != MessageType.typing)
        .toList();
    if (safe.isNotEmpty) _entries[key] = safe;
    while (_entries.length > _maxConversations) {
      _entries.remove(_entries.keys.first);
    }
  }

  static void removeMessage(String accountID, String? messageID) {
    if (messageID == null) return;
    _removedMessages.add((accountID, messageID));
    // A bounded tombstone window also protects an outdated latestMsg seed.
    while (_removedMessages.length > 1024) {
      _removedMessages.remove(_removedMessages.first);
      // An old request may contain an ID whose tombstone was just evicted.
      // Re-read the SDK instead of transferring that snapshot or writing it
      // back. An outdated conversation.latestMsg is no longer a safe seed.
      _epoch++;
      _latestSeedSafe = false;
    }
    for (final entry in _entries.entries) {
      if (entry.key.$1 == accountID) {
        entry.value.removeWhere((m) => m.clientMsgID == messageID);
      }
    }
  }

  static void removeConversation(String accountID, String conversationID) {
    final key = (accountID, conversationID);
    _entries.remove(key);
    _conversationRevisions.remove(key);
    _conversationRevisions[key] = ++_nextRevision;
    // Keep invalidation memory bounded. Advancing the floor also invalidates
    // very old requests whose individual tombstone has been evicted.
    while (_conversationRevisions.length > 1024) {
      final oldest = _conversationRevisions.keys.first;
      _revisionFloor = _conversationRevisions.remove(oldest)!;
    }
  }

  static void clear() {
    _epoch++;
    _entries.clear();
    _removedMessages.clear();
    _conversationRevisions.clear();
    _nextRevision = _revisionFloor = 0;
    _latestSeedSafe = true;
  }
}
