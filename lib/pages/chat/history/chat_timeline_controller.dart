import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/chat_history_cache.dart';
import 'chat_history_loader.dart';
import 'chat_history_diagnostics.dart';

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
    this.canTrimHistory,
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
  final bool Function(bool older)? canTrimHistory;
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
  final historyScanLimited = false.obs;
  final viewingHistory = false.obs;
  final newerHasMore = false.obs;
  final windowRevision = 0.obs;

  bool _initialized = false;
  bool _disposed = false;
  bool _timelineDirty = true;
  bool _identityDirty = true;
  bool _appending = false;
  Message? _lastLiveAnchor;
  final _identities = <String?>{};

  bool containsMessage(String? id) {
    if (_identityDirty || !_initialized) {
      _identities.clear();
      _identities.addAll(messageList.map((message) => message.clientMsgID));
      _identityDirty = false;
    }
    return _identities.contains(id) ||
        scrollingCacheMessageList.any((message) => message.clientMsgID == id);
  }

  bool _groupInfoRequested = false;
  Worker? _messageListWorker;
  Timer? _cacheTimer;
  int _cacheEpoch = 0;
  int _cacheRevision = 0;

  bool get _closed => _disposed || isClosed();
  // Cached rows are first-frame snapshots until an SDK page establishes cursors.
  bool get hasLoadedHistory => _history.loaded;

  late final ChatHistoryLoader _history = ChatHistoryLoader(
    diagnostic: (event) => ChatHistoryDiagnostics.record(conversationID, event),
    pageSize: pageSize,
    fetch: fetch,
    fetchNewer: fetchNewer,
    preserveReading: preserveReading,
    canTrimHistory: canTrimHistory,
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
      if (!_appending) {
        _identityDirty = true;
        _identities.clear();
      }
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
        cached.add(ChatHistoryCache.applyRevocation(accountID, latest));
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
    historyScanLimited.value = _history.scanLimited;
    viewingHistory.value = _history.viewingHistory;
    newerHasMore.value = _history.hasNewer;
    windowRevision.value = _history.windowRevision;
  }

  void _replaceHistory(List<Message> messages, bool firstPage, bool refresh) {
    if (_closed) return;
    // Retain the last observed live edge when installing an older date window.
    _rememberRecoveryAnchor(messageList);
    _rememberRecoveryAnchor(messages);
    final offset = captureOffset();
    messageList.value = messages
        .map((m) => ChatHistoryCache.applyRevocation(accountID, m))
        .toList();
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

  Future<AdvancedMessage> readNewerForRecovery(
          {required int count, Message? startMsg}) =>
      _history.readNewerForRecovery(count: count, startMsg: startMsg);

  Message? get recoveryAnchor {
    _rememberRecoveryAnchor(messageList);
    _rememberRecoveryAnchor(scrollingCacheMessageList);
    return _lastLiveAnchor;
  }

  void _rememberRecoveryAnchor(Iterable<Message> messages) {
    for (final message in messages) {
      if (message.clientMsgID?.isNotEmpty != true ||
          (message.seq ?? 0) <= 0 ||
          message.contentType == MessageType.typing ||
          message.status == MessageStatus.sending ||
          message.status == MessageStatus.failed) {
        continue;
      }
      if (_lastLiveAnchor == null || message.seq! > _lastLiveAnchor!.seq!) {
        _lastLiveAnchor = message;
      }
    }
  }

  static const automaticWindowLimit = 600;
  static const bufferedWindowLimit = 100;

  /// Publish append and automatic eviction together, retaining retry rows.
  void appendIncoming(Message message, {required bool trim}) {
    _rememberRecoveryAnchor([message]);
    if (_identityDirty) containsMessage(message.clientMsgID);
    var next = List<Message>.of(messageList);
    var insertion = next.length;
    if (next.isNotEmpty &&
        ChatHistoryLoader.compareMessageOrder(message, next.last) < 0) {
      var low = 0, high = next.length;
      while (low < high) {
        final middle = (low + high) >> 1;
        if (ChatHistoryLoader.compareMessageOrder(next[middle], message) <= 0) {
          low = middle + 1;
        } else {
          high = middle;
        }
      }
      insertion = low;
    }
    next.insert(insertion, message);
    var retainedIncoming = true;
    var evicted = false;
    if (trim &&
        !_history.viewingHistory &&
        next.length > automaticWindowLimit) {
      final start = next.length - automaticWindowLimit;
      retainedIncoming = insertion >= start ||
          message.status == MessageStatus.sending ||
          message.status == MessageStatus.failed;
      final retained = <Message>[
        for (var i = 0; i < next.length; i++)
          if (i >= start ||
              next[i].status == MessageStatus.sending ||
              next[i].status == MessageStatus.failed)
            next[i],
      ];
      evicted = retained.length < next.length;
      for (var i = 0; i < start; i++) {
        if (next[i].status != MessageStatus.sending &&
            next[i].status != MessageStatus.failed) {
          _identities.remove(next[i].clientMsgID);
        }
      }
      next = retained;
    }
    _appending = true;
    try {
      messageList.value = next;
    } finally {
      _appending = false;
    }
    if (retainedIncoming) _identities.add(message.clientMsgID);
    if (evicted) _history.didTrimLatest();
  }

  bool holdForIncoming({required bool awayFromLatest}) {
    if (awayFromLatest && messageList.length >= automaticWindowLimit) {
      _history.holdCurrentWindow();
    }
    return _history.viewingHistory;
  }

  void bufferIncoming(Message message) {
    _rememberRecoveryAnchor([message]);
    scrollingCacheMessageList.add(message);
    if (scrollingCacheMessageList.length > bufferedWindowLimit) {
      scrollingCacheMessageList.removeAt(0);
    }
    // These are presentation snapshots; the SDK owns every persisted message.
  }

  void trimLatestWindow() {
    if (_closed ||
        _history.viewingHistory ||
        messageList.length <= automaticWindowLimit) {
      return;
    }
    final firstLatest = messageList.length - automaticWindowLimit;
    final retained = <Message>[
      // Pending/retry rows can outlive the automatic window. Keeping them
      // must not evict the newest successful messages instead.
      for (var index = 0; index < messageList.length; index++)
        if (index >= firstLatest ||
            messageList[index].status == MessageStatus.sending ||
            messageList[index].status == MessageStatus.failed)
          messageList[index],
    ];
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

  void revoke(RevokedInfo info) {
    if (_closed || info.clientMsgID == null) return;
    ChatHistoryCache.revokeMessage(accountID, info);
    for (final list in [messageList, scrollingCacheMessageList]) {
      for (var i = 0; i < list.length; i++) {
        if (list[i].clientMsgID == info.clientMsgID) {
          list[i] = ChatHistoryCache.applyRevocation(accountID, list[i]);
        }
      }
    }
  }

  /// Invalidates pending/queued history. The route clears voice/reply state for
  /// the returned IDs while this owner clears its own lists and snapshot.
  Set<String> clear() {
    if (_closed) return <String>{};
    _lastLiveAnchor = null;
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
    _identities.clear();
    _cacheTimer?.cancel();
  }
}
