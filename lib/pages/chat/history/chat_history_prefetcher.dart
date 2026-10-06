import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/chat_history_cache.dart';

typedef LatestHistoryReader = Future<AdvancedMessage> Function(
    String conversationID, int count);

/// Transfers one native local-history read started before route construction
/// to that route. It does not persist a second message database.
class ChatHistoryPrefetcher {
  ChatHistoryPrefetcher({
    required this.accountID,
    required this.token,
    required this.epoch,
    required this.fetch,
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
    fetch: (id, count) => OpenIM.iMManager.messageManager
        .getAdvancedHistoryMessageList(conversationID: id, count: count),
  );

  final String Function() accountID;
  final String? Function() token;
  final int Function() epoch;
  final LatestHistoryReader fetch;
  final bool Function(String, String?) _isRemoved;
  final int Function(String, String) _conversationRevision;
  final Duration lifetime;
  final _requests = <(String, String?, int, String, int), _PreparedHistory>{};

  (String, String?, int, String, int) _key(String id) {
    final account = accountID();
    return (account, token(), epoch(), id, _conversationRevision(account, id));
  }

  void prepare(ConversationInfo conversation, {int count = 40}) {
    final key = _key(conversation.conversationID);
    if (key.$1.isEmpty ||
        key.$4.isEmpty ||
        conversation.isPrivateChat == true) {
      return;
    }
    if (_requests.containsKey(key)) return;
    while (_requests.length >= 12) {
      _requests.remove(_requests.keys.first)?.expiry.cancel();
    }
    final request =
        _PreparedHistory(Future.sync(() => fetch(key.$4, count)), count);
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
    final key = _key(conversation.conversationID);
    final request = _requests.remove(key);
    request?.expiry.cancel();
    if (conversation.isPrivateChat == true ||
        request == null ||
        request.count != count) {
      return fetch(conversation.conversationID, count);
    }
    final result = await request.result;
    if (key.$1 != accountID() || key.$2 != token()) {
      throw StateError('Chat session changed during history preparation');
    }
    if (key.$3 != epoch()) {
      return fetch(conversation.conversationID, count);
    }
    if (key.$5 != _conversationRevision(key.$1, key.$4)) {
      return AdvancedMessage(messageList: [], isEnd: true, errCode: 0);
    }
    // Deletion callbacks can arrive before the route owns its subscriptions.
    result.messageList = result.messageList
        ?.where((message) => !_isRemoved(key.$1, message.clientMsgID))
        .toList();
    return result;
  }

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
