import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/chat_history_cache.dart';
import 'chat_history_loader.dart';

/// Owns a chat route's message window, paging state and first-frame snapshot.
/// SDK subscriptions, scroll resources and other message workflows stay with
/// their route/module owners and use these explicit lists and callbacks.
class ChatTimelineController {
  ChatTimelineController({
    required this.accountID,
    required this.conversation,
    required this.fetch,
    this.fetchNewer,
    required this.isClosed,
    required this.onFirstPage,
    required this.captureOffset,
    required this.restoreOffset,
    required this.onFirstLoaded,
    this.timelineTimeMarker,
    this.preserveReading,
    this.pageSize = 40,
    String Function()? currentAccountID,
    bool Function()? isSessionCurrent,
  })  : conversationID = conversation().conversationID,
        _currentAccountID = currentAccountID ?? (() => OpenIM.iMManager.userID),
        _isSessionCurrent = isSessionCurrent ?? (() => true);

  final String accountID;
  final String conversationID;
  final ConversationInfo Function() conversation;
  final ChatHistoryReader fetch;
  final ChatHistoryReader? fetchNewer;
  final bool Function() isClosed;
  final VoidCallback onFirstPage;
  final double Function() captureOffset;
  final void Function(double) restoreOffset;
  final VoidCallback onFirstLoaded;
  final void Function(List<Message> messages)? timelineTimeMarker;
  final bool Function()? preserveReading;
  final int pageSize;
  final String Function() _currentAccountID;
  final bool Function() _isSessionCurrent;

  final messageList = <Message>[].obs;
  final scrollingCacheMessageList = <Message>[];
  final removedIDs = <String>{};
  final initialHistoryLoading = true.obs;
  final historyLoading = false.obs;
  final historyError = RxnString();
  final historyHasMore = true.obs;
  final viewingHistory = false.obs;
  final newerHasMore = false.obs;
  final windowRevision = 0.obs;

  bool _initialized = false;
  bool _disposed = false;
  bool _timelineDirty = true;
  bool _groupInfoRequested = false;
  Worker? _messageListWorker;
  Timer? _cacheTimer;
  int _cacheEpoch = 0;
  int _cacheRevision = 0;

  bool get _closed => _disposed || isClosed();
  // Cached rows are first-frame snapshots until an SDK page establishes cursors.
  bool get hasLoadedHistory => _history.loaded;

  late final ChatHistoryLoader _history = ChatHistoryLoader(
    pageSize: pageSize,
    fetch: fetch,
    fetchNewer: fetchNewer,
    preserveReading: preserveReading,
    messages: () => messageList,
    removedIDs: removedIDs,
    onStateChanged: _syncHistoryState,
    replace: _replaceHistory,
    onLoaded: () {
      if (!_groupInfoRequested && !_closed) {
        _groupInfoRequested = true;
        onFirstLoaded();
      }
    },
  );

  /// Seed only safe cached/latest messages, then query the SDK's latest page.
  /// The route can defer the query until its remaining entry wiring is ready.
  void initialize({bool prefetch = true}) {
    if (_initialized || _closed) return;
    _initialized = true;
    _cacheEpoch = ChatHistoryCache.epoch;
    _cacheRevision = ChatHistoryCache.revision(accountID, conversationID);
    _messageListWorker = ever(messageList, (_) {
      _timelineDirty = true;
      _cacheTimer?.cancel();
      _cacheTimer = Timer(const Duration(milliseconds: 80), _cacheHistory);
    });
    final info = conversation();
    if (info.isPrivateChat == true) {
      ChatHistoryCache.removeConversation(accountID, conversationID);
      _cacheRevision = ChatHistoryCache.revision(accountID, conversationID);
    } else {
      final cached = ChatHistoryCache.read(accountID, conversationID);
      final latest = info.latestMsg;
      if (ChatHistoryCache.canSeedLatest &&
          latest != null &&
          latest.clientMsgID?.isNotEmpty == true &&
          latest.sendTime != null &&
          latest.attachedInfoElem?.isPrivateChat != true &&
          latest.contentType != MessageType.typing &&
          !ChatHistoryCache.isRemoved(accountID, latest.clientMsgID) &&
          !cached.any((m) => m.clientMsgID == latest.clientMsgID)) {
        cached.add(latest);
      }
      if (cached.isNotEmpty) {
        messageList.value = ChatHistoryLoader.merge(cached);
      }
    }
    if (prefetch) unawaited(loadOlder());
  }

  void _syncHistoryState() {
    if (_closed) return;
    initialHistoryLoading.value = !_history.loaded && _history.loading;
    historyLoading.value = _history.loading;
    historyError.value = _history.error?.toString();
    historyHasMore.value = _history.hasMore;
    viewingHistory.value = _history.viewingHistory;
    newerHasMore.value = _history.hasNewer;
    windowRevision.value = _history.windowRevision;
  }

  void _replaceHistory(List<Message> messages, bool firstPage, bool refresh) {
    if (_closed) return;
    final offset = captureOffset();
    messageList.value = messages;
    final visibleIDs = messages.map((m) => m.clientMsgID).toSet();
    final latest = messages
        .where((m) =>
            m.status != MessageStatus.sending &&
            m.status != MessageStatus.failed)
        .lastOrNull;
    scrollingCacheMessageList.removeWhere((m) =>
        visibleIDs.contains(m.clientMsgID) ||
        removedIDs.contains(m.clientMsgID) ||
        (firstPage &&
            !_history.viewingHistory &&
            latest != null &&
            ((m.sendTime ?? m.createTime ?? 0) <
                    (latest.sendTime ?? latest.createTime ?? 0) ||
                ((m.sendTime ?? m.createTime ?? 0) ==
                        (latest.sendTime ?? latest.createTime ?? 0) &&
                    (m.seq ?? 0) > 0 &&
                    (m.seq ?? 0) <= (latest.seq ?? 0)))));
    if (firstPage && !_history.viewingHistory) {
      onFirstPage();
    } else if (refresh) {
      restoreOffset(offset);
    }
  }

  Future<bool> loadOlder() =>
      _closed ? Future.value(false) : _history.loadOlder();

  Future<bool> refresh() => _closed ? Future.value(false) : _history.refresh();

  static const automaticWindowLimit = 600;
  static const bufferedWindowLimit = 100;

  bool holdForIncoming({required bool awayFromLatest}) {
    if (awayFromLatest && messageList.length >= automaticWindowLimit) {
      _history.holdCurrentWindow();
    }
    return _history.viewingHistory;
  }

  void bufferIncoming(Message message) {
    scrollingCacheMessageList.add(message);
    if (scrollingCacheMessageList.length > bufferedWindowLimit) {
      scrollingCacheMessageList.removeAt(0);
    }
    // These are presentation snapshots; the SDK owns every persisted message.
  }

  void trimLatestWindow() {
    if (_history.viewingHistory || messageList.length <= automaticWindowLimit) {
      return;
    }
    var excess = messageList.length - automaticWindowLimit;
    final retained = messageList.where((m) {
      if (excess > 0 &&
          m.status != MessageStatus.sending &&
          m.status != MessageStatus.failed) {
        excess--;
        return false;
      }
      return true;
    }).toList();
    if (retained.length == messageList.length) return;
    messageList.value = retained;
    _history.didTrimLatest();
  }

  Future<bool> retry() => _closed ? Future.value(false) : _history.retry();

  Future<bool> jumpTo(Message target) =>
      _closed ? Future.value(false) : _history.jumpTo(target);

  Future<bool> loadNewer() async {
    if (_closed) return false;
    final more = await _history.loadNewer();
    if (!_closed && !_history.viewingHistory) flushBuffered();
    return more;
  }

  Future<bool> returnToLatest() =>
      _closed ? Future.value(false) : _history.returnToLatest();

  void cancelWindowChange() {
    if (!_closed) _history.cancelWindowChange();
  }

  void remove(String? id) {
    if (_closed || id == null) return;
    ChatHistoryCache.removeMessage(accountID, id);
    removedIDs.add(id);
    messageList.removeWhere((m) => m.clientMsgID == id);
    scrollingCacheMessageList.removeWhere((m) => m.clientMsgID == id);
  }

  /// Invalidates pending/queued history. The route clears voice/reply state for
  /// the returned IDs while this owner clears its own lists and snapshot.
  Set<String> clear() {
    if (_closed) return <String>{};
    _history.clear();
    _cacheTimer?.cancel();
    final ids = [...messageList, ...scrollingCacheMessageList]
        .map((message) => message.clientMsgID)
        .whereType<String>()
        .toSet();
    removedIDs.addAll(ids);
    messageList.clear();
    scrollingCacheMessageList.clear();
    // Clearing the observable list may have scheduled another cache write.
    _cacheTimer?.cancel();
    ChatHistoryCache.removeConversation(accountID, conversationID);
    _cacheRevision = ChatHistoryCache.revision(accountID, conversationID);
    return ids;
  }

  Message indexOfMessage(int index, {bool calculate = true}) {
    if (calculate && _timelineDirty) {
      final marker = timelineTimeMarker;
      if (marker == null) {
        IMUtils.calChatTimeInterval(messageList);
      } else {
        marker(messageList);
      }
      _timelineDirty = false;
    }
    return messageList[messageList.length - 1 - index];
  }

  String? getShowTime(Message message) => message.exMap['showTime'] == true
      ? IMUtils.getChatTimeline(message.sendTime!)
      : null;

  void flushBuffered() {
    if (_closed || scrollingCacheMessageList.isEmpty) return;
    messageList.value = ChatHistoryLoader.merge(
        [...messageList, ...scrollingCacheMessageList],
        removedIDs: removedIDs);
    scrollingCacheMessageList.clear();
  }

  void _cacheHistory() {
    if (_disposed ||
        !_initialized ||
        !_isSessionCurrent() ||
        _cacheEpoch != ChatHistoryCache.epoch ||
        _cacheRevision !=
            ChatHistoryCache.revision(accountID, conversationID) ||
        accountID != _currentAccountID()) {
      return;
    }
    if (conversation().isPrivateChat == true) {
      ChatHistoryCache.removeConversation(accountID, conversationID);
      _cacheRevision = ChatHistoryCache.revision(accountID, conversationID);
      return;
    }
    if (_history.viewingHistory) return;
    ChatHistoryCache.write(accountID, conversationID, messageList,
        epoch: _cacheEpoch);
  }

  void close() {
    if (_disposed) return;
    _cacheHistory();
    _disposed = true;
    _history.close();
    _messageListWorker?.dispose();
    _cacheTimer?.cancel();
  }
}
