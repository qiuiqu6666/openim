import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/chat_history_cache.dart';
import '../../chat/history/chat_history_loader.dart';

/// A read-only history window for one preview. It owns no SDK listeners,
/// receipts or chat controller, and reuses the account's existing safe cache.
class ConversationPeekLoader extends ChangeNotifier {
  ConversationPeekLoader({
    required this.conversation,
    ChatHistoryReader? fetch,
    String Function()? currentAccountID,
    String? Function()? currentToken,
    this.pageSize = 30,
  })  : conversationID = conversation.conversationID,
        _currentAccountID = currentAccountID ?? (() => OpenIM.iMManager.userID),
        _currentToken = currentToken ?? (() => DataSp.chatToken) {
    _accountID = _currentAccountID();
    _token = _currentToken();
    _epoch = ChatHistoryCache.epoch;
    _revision = ChatHistoryCache.revision(_accountID, conversationID);
    _fetch = fetch ??
        ({required count, startMsg}) => OpenIM.iMManager.messageManager
            .getAdvancedHistoryMessageList(
                conversationID: conversationID,
                count: count,
                startMsg: startMsg);
  }

  final ConversationInfo conversation;
  final String conversationID;
  final int pageSize;
  final String Function() _currentAccountID;
  final String? Function() _currentToken;
  late final String _accountID;
  late final String? _token;
  late final int _epoch;
  late final int _revision;
  late final ChatHistoryReader _fetch;

  final _messages = <Message>[];
  Message? _cursor;
  Future<bool>? _request;
  bool _seeded = false;
  bool _disposed = false;
  bool loading = false;
  bool loadingOlder = false;
  bool loaded = false;
  bool hasMoreOlder = true;
  Object? error;
  Object? olderError;

  bool get _current =>
      !_disposed &&
      _accountID.isNotEmpty &&
      _token != null &&
      conversationID.isNotEmpty &&
      _accountID == _currentAccountID() &&
      _token == _currentToken() &&
      _epoch == ChatHistoryCache.epoch &&
      _revision == ChatHistoryCache.revision(_accountID, conversationID);

  bool get isCurrent => _current;

  /// Chronological clones: preview rendering cannot change cached read state.
  /// Tombstones and expired content are checked again whenever the UI reads it.
  List<Message> get messages => !_current
      ? const []
      : List<Message>.unmodifiable(_messages.where(_visible));

  Future<bool> loadInitial() {
    if (!_current) return _invalidate();
    if (_request != null) return _request!;
    if (loaded) return Future.value(true);
    if (!_seeded) {
      _seeded = true;
      if (conversation.isPrivateChat != true) {
        final cached = _prepare(
            ChatHistoryCache.read(_accountID, conversationID),
            cached: true);
        _messages.addAll(cached.length > pageSize
            ? cached.sublist(cached.length - pageSize)
            : cached);
      }
    }
    return _start(initial: true);
  }

  Future<bool> loadOlder() {
    if (!_current) return _invalidate();
    if (_request != null) return _request!;
    if (!loaded) return loadInitial();
    if (!hasMoreOlder || _cursor == null) return Future.value(false);
    return _start(initial: false);
  }

  Future<bool> retry() => loaded ? retryOlder() : loadInitial();
  Future<bool> retryOlder() => loadOlder();

  Future<bool> _start({required bool initial}) {
    final completion = Completer<bool>();
    _request = completion.future;
    if (initial) {
      loading = true;
      error = null;
    } else {
      loadingOlder = true;
      olderError = null;
    }
    notifyListeners();
    unawaited(_load(initial: initial).then((success) {
      _request = null;
      loading = loadingOlder = false;
      if (!_disposed) notifyListeners();
      completion.complete(success);
    }));
    return completion.future;
  }

  Future<bool> _load({required bool initial}) async {
    try {
      if (!_current) return await _invalidate(notify: false);
      final previousCursor = _cursor?.clientMsgID;
      final result =
          await _fetch(count: pageSize, startMsg: initial ? null : _cursor);
      if (!_current) return await _invalidate(notify: false);
      if (result.errCode != null && result.errCode != 0) {
        throw StateError(
            'History load failed (${result.errCode}): ${result.errMsg ?? ''}');
      }
      final raw = result.messageList ?? const <Message>[];
      final page = _prepare(raw);
      // Paging uses the SDK boundary even if that message is typing, removed
      // or expired. Filtering the visible page must not skip older history.
      final oldest = ChatHistoryLoader.merge(raw)
          .where((m) => m.clientMsgID?.isNotEmpty == true)
          .firstOrNull;
      final nextCursor = oldest?.clientMsgID;
      hasMoreOlder = result.isEnd != true &&
          nextCursor != null &&
          (initial || nextCursor != previousCursor);
      if (nextCursor != null) _cursor = Message(clientMsgID: nextCursor);
      if (initial) {
        _messages
          ..clear()
          ..addAll(page);
        loaded = true;
        olderError = null;
        if (conversation.isPrivateChat != true) {
          ChatHistoryCache.write(
              _accountID, conversationID, _prepare(page, cached: true),
              epoch: _epoch);
        }
      } else {
        final merged = ChatHistoryLoader.merge([..._messages, ...page]);
        _messages
          ..clear()
          ..addAll(merged.where(_visible));
      }
      return true;
    } catch (failure) {
      if (!_current) return await _invalidate(notify: false);
      if (initial) {
        error = failure;
      } else {
        olderError = failure;
      }
      return false;
    }
  }

  bool _visible(Message message) =>
      message.contentType != MessageType.typing &&
      !ChatHistoryCache.isRemoved(_accountID, message.clientMsgID) &&
      !message.hasExpired;

  /// The preview shows a placeholder for these messages, never their content.
  static bool isPrivateMessage(Message message) {
    if (message.attachedInfoElem?.isPrivateChat == true ||
        (message.attachedInfoElem?.burnDuration ?? 0) > 0) {
      return true;
    }
    final serialized = message.attachedInfo;
    if (serialized == null || serialized.trim().isEmpty) return false;
    try {
      final info = AttachedInfoElem.fromJson(
          jsonDecode(serialized) as Map<String, dynamic>);
      return info.isPrivateChat == true || (info.burnDuration ?? 0) > 0;
    } catch (_) {
      // Quoted/merged messages can carry only serialized retention metadata.
      return true;
    }
  }

  /// Referenced private content also stays out of shared safe-history seeds.
  static bool containsPrivateContent(Message message, [int depth = 0]) {
    if (isPrivateMessage(message) || depth >= 8) return true;
    final quoted = message.quoteElem?.quoteMessage;
    if (quoted != null && containsPrivateContent(quoted, depth + 1)) {
      return true;
    }
    return message.mergeElem?.multiMessage
            ?.any((item) => containsPrivateContent(item, depth + 1)) ==
        true;
  }

  List<Message> _prepare(Iterable<Message> source, {bool cached = false}) {
    final copies = <Message>[];
    for (final message in source) {
      final copy = Message.fromJson(
          jsonDecode(jsonEncode(message.toJson())) as Map<String, dynamic>);
      // Some SDK snapshots only have the serialized attachedInfo metadata.
      final serialized = copy.attachedInfo;
      if (serialized != null && serialized.trim().isNotEmpty) {
        try {
          final info = AttachedInfoElem.fromJson(
              jsonDecode(serialized) as Map<String, dynamic>);
          if (copy.attachedInfoElem == null) {
            copy.attachedInfoElem = info;
          } else if (info.isPrivateChat == true) {
            copy.attachedInfoElem!.isPrivateChat = true;
            copy.attachedInfoElem!.burnDuration ??= info.burnDuration;
            copy.attachedInfoElem!.hasReadTime ??= info.hasReadTime;
          }
        } catch (_) {
          // Unknown retention metadata cannot safely expose cached content.
          continue;
        }
      }
      if (_visible(copy) && (!cached || !containsPrivateContent(copy))) {
        copies.add(copy);
      }
    }
    return ChatHistoryLoader.merge(copies);
  }

  Future<bool> _invalidate({bool notify = true}) {
    _messages.clear();
    _cursor = null;
    loading = loadingOlder = false;
    loaded = false;
    hasMoreOlder = false;
    error = olderError = null;
    if (notify && !_disposed) notifyListeners();
    return Future.value(false);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _messages.clear();
    _cursor = null;
    loading = loadingOlder = false;
    super.dispose();
  }
}
