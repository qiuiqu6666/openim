import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/legacy_identity/legacy_server_snapshot.dart';
export '../../../services/legacy_identity/legacy_server_snapshot.dart'
    show LegacyCleanupSession, LegacyCleanupPost;

/// Completes one server-authorized cleanup for devices with an older SDK cache.
/// The SDK's incremental conversation sync deliberately skips local deletions.
class LegacyServiceConversationCleanup {
  LegacyServiceConversationCleanup({
    LegacyCleanupSession? Function()? session,
    Future<List<ConversationInfo>> Function(int offset, int count)? readPage,
    Future<List<ConversationInfo>> Function(String id)? readConversation,
    Future<AdvancedMessage> Function(String id, Message? start)? readHistory,
    Future<void> Function(String id, String clientMsgID)? deleteMessage,
    Future<void> Function(String id)? hideConversation,
    LegacyCleanupPost? post,
    Future<bool> Function(String key)? isCompleted,
    Future<void> Function(String key)? markCompleted,
  })  : _session = session ?? LegacyServerSnapshot.currentSession,
        _readPage = readPage ??
            ((offset, count) => OpenIM.iMManager.conversationManager
                .getConversationListSplit(offset: offset, count: count)),
        _readConversation = readConversation ??
            ((id) => OpenIM.iMManager.conversationManager
                .getMultipleConversation(conversationIDList: [id])),
        _readHistory = readHistory ??
            ((id, start) => OpenIM.iMManager.messageManager
                .getAdvancedHistoryMessageList(
                    conversationID: id,
                    startMsg: start,
                    count: 100,
                    viewType: GetHistoryViewType.search)),
        _deleteMessage = deleteMessage ??
            ((id, messageID) async => OpenIM.iMManager.messageManager
                .deleteMessageFromLocalStorage(
                    conversationID: id, clientMsgID: messageID)),
        _hideConversation = hideConversation ??
            ((id) async => OpenIM.iMManager.conversationManager
                .hideConversation(conversationID: id)),
        _post = post ?? LegacyServerSnapshot.defaultPost,
        _isCompleted = isCompleted ?? _readCompleted,
        _markCompleted = markCompleted ?? _writeCompleted;

  static const epoch = 'legacy-official-contact-removal-20261010-v1';
  static const cutoffMilliseconds = 1791582008267;
  static const peers = {
    'im_5ff61c4e25466a7ff2ecd711c09c0702',
    'im_5882da9ecbe9a9e10cc9cc7c9be4fb72',
  };
  static const _pageSize = 400;
  final LegacyCleanupSession? Function() _session;
  final Future<List<ConversationInfo>> Function(int, int) _readPage;
  final Future<List<ConversationInfo>> Function(String) _readConversation;
  final Future<AdvancedMessage> Function(String, Message?) _readHistory;
  final Future<void> Function(String, String) _deleteMessage;
  final Future<void> Function(String) _hideConversation;
  final LegacyCleanupPost _post;
  final Future<bool> Function(String) _isCompleted;
  final Future<void> Function(String) _markCompleted;
  Future<void>? _pending;

  Future<void> run({
    required bool Function() isActive,
    required void Function(ConversationInfo) onDeleted,
  }) {
    if (_pending != null) return _pending!;
    final task = _run(isActive, onDeleted);
    _pending = task;
    return task.whenComplete(() {
      if (identical(_pending, task)) _pending = null;
    });
  }

  Future<void> _run(bool Function() isActive,
      void Function(ConversationInfo) onDeleted) async {
    final session = _session();
    if (session == null ||
        !LegacyServerSnapshot.allowedServer(session.server)) {
      return;
    }
    bool current() => isActive() && _session() == session;
    if (!current()) return;
    try {
      // Freeze the entire paginated snapshot before any deletion can shift it.
      final local = <String, ConversationInfo>{};
      var offset = 0;
      while (current()) {
        final page = await _readPage(offset, _pageSize);
        if (!current()) return;
        for (final item in page) {
          // Duplicate pages indicate a changing or invalid snapshot; retry later.
          if (local.containsKey(item.conversationID)) return;
          local[item.conversationID] = item;
        }
        if (page.length < _pageSize) break;
        offset += page.length;
      }
      final candidates = local.values
          .where((item) => _eligible(session.owner, item))
          .toList(growable: false);
      if (candidates.isEmpty || !current()) return;
      final serverIDs =
          await LegacyServerSnapshot.serverIDs(session, post: _post);
      if (!current()) return;
      for (final candidate in candidates) {
        if (!current()) return;
        final id = candidate.conversationID;
        if (serverIDs.contains(id)) continue;
        final key = '$epoch|${session.server}|${session.owner}|$id';
        final completed = await _isCompleted(key);
        if (!current()) return;
        if (completed) continue;
        // A new server conversation or local message wins over this old snapshot.
        final latestServerIDs =
            await LegacyServerSnapshot.serverIDs(session, post: _post);
        if (!current()) return;
        if (latestServerIDs.contains(id)) continue;
        final latest = await _readConversation(id);
        if (!current()) return;
        if (latest.length != 1 ||
            latest.single.conversationID != id ||
            !_eligible(session.owner, latest.single)) {
          continue;
        }
        try {
          // Read the complete visible history before deleting: never shift a
          // pagination anchor or delete messages arriving after this snapshot.
          final messages = <String, Message>{};
          Message? start;
          while (current()) {
            final page = await _readHistory(id, start);
            if (!current()) return;
            if ((page.errCode ?? 0) != 0) {
              throw const FormatException('Conversation history unavailable');
            }
            final items = page.messageList ?? <Message>[];
            for (final message in items) {
              final messageID = message.clientMsgID;
              if (messageID == null ||
                  messageID.isEmpty ||
                  messages.containsKey(messageID)) {
                throw const FormatException('Unstable conversation history');
              }
              messages[messageID] = message;
            }
            if (page.isEnd == true) break;
            if (items.isEmpty) {
              throw const FormatException('Incomplete conversation history');
            }
            start = items.first;
          }
          var safeToHide = true;
          for (final message in messages.values) {
            if (!current()) return;
            if (!_oldMessage(message)) {
              safeToHide = false;
              continue;
            }
            await _deleteMessage(id, message.clientMsgID!);
            if (!current()) return;
          }
          if (!safeToHide) continue;
          // Both mutations below are local-only. In particular this maintenance
          // path must never call the SDK's server-wide clear-conversation API.
          final finalServerIDs =
              await LegacyServerSnapshot.serverIDs(session, post: _post);
          if (!current()) return;
          if (finalServerIDs.contains(id)) continue;
          final finalLocal = await _readConversation(id);
          if (!current()) return;
          if (finalLocal.length != 1 ||
              finalLocal.single.conversationID != id ||
              !_eligible(session.owner, finalLocal.single)) {
            continue;
          }
          await _hideConversation(id);
          if (!current()) return;
          onDeleted(finalLocal.single);
          // Persist only after exact local message deletion and local hide finish.
          await _markCompleted(key);
          if (!current()) return;
        } catch (_) {
          if (!current()) return;
          // Keep failed items visible and retry on a later sync/refresh.
        }
      }
    } catch (_) {
      // An unavailable or malformed authoritative response never authorizes deletion.
    }
  }

  static bool _oldMessage(Message message) {
    final time = message.sendTime;
    return (message.seq ?? 0) > 0 &&
        time != null &&
        time > 0 &&
        time <= cutoffMilliseconds &&
        (message.createTime ?? 0) <= cutoffMilliseconds;
  }

  static bool _eligible(String owner, ConversationInfo item) {
    final peer = item.userID;
    if (item.conversationType != ConversationType.single ||
        (item.groupID?.isNotEmpty ?? false) ||
        peer == null ||
        (!peers.contains(peer) && !peers.contains(owner)) ||
        peer == owner) {
      return false;
    }
    final pair = [owner, peer]..sort();
    if (item.conversationID != 'si_${pair.join('_')}') return false;
    final time = item.latestMsgSendTime;
    if (time == null || time <= 0 || time > cutoffMilliseconds) return false;
    if ((item.latestMsg?.sendTime ?? 0) > cutoffMilliseconds ||
        (item.latestMsg?.createTime ?? 0) > cutoffMilliseconds ||
        (item.draftTextTime ?? 0) > cutoffMilliseconds) {
      return false;
    }
    // An undated draft or pending local send cannot be proven to predate cleanup.
    if ((item.draftText?.isNotEmpty ?? false) &&
        (item.draftTextTime ?? 0) <= 0) {
      return false;
    }
    if (item.latestMsg != null && (item.latestMsg!.seq ?? 0) <= 0) return false;
    return true;
  }

  static Future<bool> _readCompleted(String key) async =>
      (await SharedPreferences.getInstance()).getBool(key) == true;

  static Future<void> _writeCompleted(String key) async {
    if (!await (await SharedPreferences.getInstance()).setBool(key, true)) {
      throw StateError('Conversation cleanup completion was not stored');
    }
  }
}
