import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/chat_history_cache.dart';
import '../../../core/session/queries/sdk_query_gate.dart';

typedef LatestHistoryReader = Future<AdvancedMessage> Function(
    String conversationID, int count);

/// Starts local proof warming and remote preparation before route construction.
/// The SDK owns local copies; the remote request is transferred to the route.
class ChatHistoryPrefetcher {
  ChatHistoryPrefetcher({
    required this.accountID,
    required this.token,
    required this.epoch,
    required this.fetch,
    this.fetchLocalWindow,
    bool Function(String, String?)? isRemoved,
    int Function(String, String)? conversationRevision,
    this.lifetime = const Duration(seconds: 2),
  })  : _isRemoved = isRemoved ?? ChatHistoryCache.isRemoved,
        _conversationRevision =
            conversationRevision ?? ChatHistoryCache.revision;

  static final shared = ChatHistoryPrefetcher(
    accountID: () => OpenIM.iMManager.userID,
    token: () => DataSp.chatToken,
    epoch: () => ChatHistoryCache.epoch,
    fetchLocalWindow: (id, count) => OpenIM.iMManager.messageManager
        .getLocalMessageWindow(conversationID: id, count: count),
    fetch: (id, count) => OpenIM.iMManager.messageManager
        .getAdvancedHistoryMessageList(
            conversationID: id, count: count, messageWindow: true),
  );

  final String Function() accountID;
  final String? Function() token;
  final int Function() epoch;
  final LatestHistoryReader fetch;
  final LatestHistoryReader? fetchLocalWindow;
  final bool Function(String, String?) _isRemoved;
  final int Function(String, String) _conversationRevision;
  final Duration lifetime;
  final _requests =
      <(String, String?, int, String, int, int), _PreparedHistory>{};
  final _reads = SdkQueryGate<AdvancedMessage>(limit: 2);
  final _localReads = SdkQueryGate<AdvancedMessage>(limit: 2);
  static const _readTimeout = Duration(seconds: 30);

  (String, String?, int, String, int, int) _key(String id) {
    final account = accountID();
    return (
      account,
      token(),
      epoch(),
      id,
      _conversationRevision(account, id),
      ChatHistoryCache.messageRevision
    );
  }

  (String, String?, int, String, int, int)? _preparedKey(
      (String, String?, int, String, int, int) key, int count) {
    for (final entry in _requests.entries) {
      final candidate = entry.key;
      if ((
                candidate.$1,
                candidate.$2,
                candidate.$3,
                candidate.$4,
                candidate.$5
              ) ==
              (key.$1, key.$2, key.$3, key.$4, key.$5) &&
          entry.value.count == count) {
        return candidate;
      }
    }
    return null;
  }

  void prepare(ConversationInfo conversation,
      {int count = 40, void Function(String)? mark}) {
    final key = _key(conversation.conversationID);
    if (key.$1.isEmpty ||
        key.$4.isEmpty ||
        conversation.isPrivateChat == true) {
      return;
    }
    // Warm the SDK's own attested cache. The page joins its pending read or
    // consumes its completed copy; Flutter retains no second local snapshot.
    if (fetchLocalWindow != null && !_localReads.isFull) {
      mark?.call('local_window_start');
      unawaited(_localReads.run(
          (key, count), () => fetchLocalWindow!(key.$4, count),
          timeout: _readTimeout,
          isCurrent: () =>
              key.$1 == accountID() &&
              key.$2 == token() &&
              key.$3 == epoch()).then<void>(
          (_) => mark?.call('local_window_finished'),
          onError: (Object _) => mark?.call('local_window_failed')));
    }
    if (_preparedKey(key, count) != null || _reads.isFull) return;
    while (_requests.length >= 12) {
      _requests.remove(_requests.keys.first)?.expiry.cancel();
    }
    final request = _PreparedHistory(_read(key, count), count);
    _requests[key] = request;
    request.expiry = Timer(lifetime, () {
      if (identical(_requests[key], request)) _requests.remove(key);
    });
    // A cancelled navigation must not leave an unobserved native read error.
    unawaited(request.result.then<void>((_) {}, onError: (Object error) {
      if (identical(_requests[key], request)) {
        _requests.remove(key);
        request.expiry.cancel();
      }
    }));
  }

  Future<AdvancedMessage> readLatest(ConversationInfo conversation,
      {int count = 40}) async {
    final currentKey = _key(conversation.conversationID);
    // An unrelated conversation's delivery must not fork an in-flight window.
    // Keep its original revision so legacy responses still revalidate below.
    final key = _preparedKey(currentKey, count) ?? currentKey;
    final request = _requests.remove(key);
    request?.expiry.cancel();
    if (conversation.isPrivateChat == true ||
        request == null ||
        request.count != count) {
      return _read(key, count);
    }
    final result = await request.result;
    if (key.$1 != accountID() || key.$2 != token()) {
      throw StateError('Chat session changed during history preparation');
    }
    if (key.$3 != epoch()) {
      return _read(_key(conversation.conversationID), count);
    }
    if (key.$5 != _conversationRevision(key.$1, key.$4)) {
      return AdvancedMessage(messageList: [], isEnd: true, errCode: 0);
    }
    if (key.$6 != ChatHistoryCache.messageRevision &&
        result.window?.canPublish != true) {
      return _read(_key(conversation.conversationID), count);
    }
    // Deletion callbacks can arrive before the route owns its subscriptions.
    result.messageList = result.messageList
        ?.where((message) => !_isRemoved(key.$1, message.clientMsgID))
        .toList();
    return result;
  }

  Future<AdvancedMessage> _read(
          (String, String?, int, String, int, int) key, int count) =>
      _reads.run((key, count), () => fetch(key.$4, count),
          timeout: _readTimeout,
          isCurrent: () => key.$1 == accountID() && key.$2 == token());

  void clear() {
    for (final request in _requests.values) {
      request.expiry.cancel();
    }
    _requests.clear();
  }
}

class _PreparedHistory {
  _PreparedHistory(this.result, this.count);
  final Future<AdvancedMessage> result;
  final int count;
  late final Timer expiry;
}
