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
    this.fetchLocalSnapshot,
    this.fetchWindow,
    this.canPaintInitialWindow,
    this.onLatestDeferred,
    this.beforeLatestReplace,
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
  final Future<List<Message>> Function()? fetchLocalSnapshot;
  final FutureOr<AdvancedMessage> Function()? fetchWindow;
  MessageWindow? _publishedWindow;
  bool get hasPublishableWindow => _publishedWindow?.canPublish == true;
  bool get _hasSnapshotProvider =>
      fetchLocalSnapshot != null || fetchWindow != null;
  late final _ingress = MessageWindowIngress(
    conversationID: conversationID,
    publish: _appendWindowBatch,
    recover: () {
      if (!_closed) unawaited(refresh());
    },
  );
  final bool Function()? canPaintInitialWindow;
  final void Function()? onLatestDeferred;
  final Future<void> Function()? beforeLatestReplace;
  bool _hasPaintedRows = false;
  final latestDeferred = false.obs;

  void recordPaintedRows(List<String> ids) {
    if (!_closed && ids.any(containsMessage)) _hasPaintedRows = true;
  }

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
  final initialWindowReady = false.obs;
  final historyLoading = false.obs;
  final historyPagingLoading = false.obs;
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
  final _snapshotIDs = <String?>{};

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

  void showLoadedLocalWindow() {
    if (!_closed && _history.loaded && canPaintInitialWindow?.call() != false) {
      initialWindowReady.value = true;
    }
  }

  late final ChatHistoryLoader _history = ChatHistoryLoader(
    diagnostic: (event) => ChatHistoryDiagnostics.record(conversationID, event),
    pageSize: pageSize,
    fetch: ({required count, startMsg}) async {
      final result = await fetch(count: count, startMsg: startMsg);
      if (result.window != null &&
          result.window!.conversationID != conversationID) {
        throw StateError('History window belongs to another conversation');
      }
      if (result.window?.canPublish == true &&
          hasPublishableWindow &&
          result.window!.targetWatermark < _publishedWindow!.targetWatermark) {
        // A pre-navigation snapshot may finish after a newer local window.
        // Read the SDK's current proof; never roll the published edge backwards.
        final current = await fetchWindow?.call();
        if (current?.window?.canPublish != true ||
            current!.window!.conversationID != conversationID ||
            current.window!.targetWatermark <
                _publishedWindow!.targetWatermark) {
          throw StateError(
              'History snapshot superseded by the published window');
        }
        return current;
      }
      return result;
    },
    isDisplaySnapshot: (id) => _snapshotIDs.contains(id),
    hasPaintedRows: () => _hasPaintedRows,
    expectsLatest: () {
      final latest = conversation().latestMsg;
      return latest?.clientMsgID?.isNotEmpty == true &&
          !ChatHistoryCache.isRemoved(accountID, latest!.clientMsgID) &&
          latest.contentType != MessageType.typing;
    },
    beforeLatestReplace: beforeLatestReplace,
    onLatestDeferred: () {
      latestDeferred.value = true;
      onLatestDeferred?.call();
    },
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

  /// Production routes paint an attested native window or the complete SDK
  /// page. The route may defer the query until entry wiring is ready.
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
    } else if (!_hasSnapshotProvider) {
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
    // Production entry paints only an attested native window, never an old
    // presentation cache plus one preview. Live arrivals remain hidden until
    // they can be committed with the initial window.
    if (!_hasSnapshotProvider) initialWindowReady.value = true;
    if (_hasSnapshotProvider &&
        info.isPrivateChat != true &&
        messageList.length < pageSize) {
      unawaited(_loadLocalSnapshot());
    }
    if (prefetch) unawaited(loadOlder());
  }

  Future<void> _loadLocalSnapshot() async {
    final revision = _history.windowRevision;
    final cacheRevision = _cacheRevision;
    final watch = Stopwatch()..start();
    try {
      final prepared = fetchWindow?.call();
      // A prewarmed proof can publish in onInit, before the first route build.
      // Awaiting an already completed Future would still paint a skeleton frame.
      final page =
          prepared is Future<AdvancedMessage> ? await prepared : prepared;
      final window = page?.window;
      final rows = page?.messageList ??
          (fetchLocalSnapshot == null
              ? <Message>[]
              : await fetchLocalSnapshot!());
      if (window != null &&
          (!window.canPublish || window.conversationID != conversationID)) {
        return;
      }
      if (_closed ||
          !_isSessionCurrent() ||
          accountID != _currentAccountID() ||
          conversation().isPrivateChat == true ||
          _history.loaded ||
          revision != _history.windowRevision ||
          _history.viewingHistory ||
          (window?.canPublish != true &&
              canPaintInitialWindow?.call() == false) ||
          _cacheEpoch != ChatHistoryCache.epoch ||
          cacheRevision !=
              ChatHistoryCache.revision(accountID, conversationID)) {
        return;
      }
      final currentIDs = messageList.map((m) => m.clientMsgID).toSet();
      final safe = rows
          .where((m) =>
              m.clientMsgID?.isNotEmpty == true &&
              m.attachedInfoElem?.isPrivateChat != true &&
              m.contentType != MessageType.typing &&
              !removedIDs.contains(m.clientMsgID) &&
              !ChatHistoryCache.isRemoved(accountID, m.clientMsgID))
          .toList();
      if (safe.isEmpty && window?.emptyConfirmed != true) return;
      final latest = conversation().latestMsg;
      if (latest?.clientMsgID?.isNotEmpty == true &&
          !safe.any((m) => m.clientMsgID == latest!.clientMsgID) &&
          !messageList.any((m) => m.clientMsgID == latest!.clientMsgID) &&
          !ChatHistoryCache.isRemoved(accountID, latest!.clientMsgID) &&
          !((latest.seq ?? 0) > 0 &&
              window != null &&
              latest.seq! <= window.targetWatermark)) {
        return;
      }
      final liveSeqs =
          messageList.where((m) => (m.seq ?? 0) > 0).map((m) => m.seq!).toSet();
      final snapshotEnd =
          safe.map((m) => m.seq ?? 0).fold(0, (a, b) => a > b ? a : b);
      final liveEnd = liveSeqs.fold(0, (a, b) => a > b ? a : b);
      if (window == null && liveEnd > snapshotEnd) {
        final stored = {...liveSeqs, ...safe.map((m) => m.seq ?? 0)};
        final start = liveEnd - pageSize + 1;
        for (var seq = start > 1 ? start : 1; seq <= liveEnd; seq++) {
          if (!stored.contains(seq)) {
            return;
          }
        }
      }
      _snapshotIDs.addAll(safe
          .map((m) => m.clientMsgID)
          .where((id) => !currentIDs.contains(id)));
      final combined = ChatHistoryLoader.merge([
        ...safe.map((m) => ChatHistoryCache.applyRevocation(accountID, m)),
        ...messageList,
      ], removedIDs: removedIDs);
      final persisted = combined
          .where((m) =>
              m.status != MessageStatus.sending &&
              m.status != MessageStatus.failed)
          .toList();
      final keep = persisted.length > pageSize
          ? persisted
              .skip(persisted.length - pageSize)
              .map((m) => m.clientMsgID)
              .toSet()
          : persisted.map((m) => m.clientMsgID).toSet();
      final initial = combined
          .where((m) =>
              keep.contains(m.clientMsgID) ||
              m.status == MessageStatus.sending ||
              m.status == MessageStatus.failed)
          .toList();
      initialWindowReady.value = true;
      if (window != null) {
        _publishedWindow = window;
        _ingress.accept(window);
      }
      messageList.value = window == null
          ? initial
          : initial
              .where((m) => (m.seq ?? 0) <= window.targetWatermark)
              .toList();
      if (window != null) {
        for (final m
            in initial.where((m) => (m.seq ?? 0) > window.targetWatermark)) {
          _ingress.receive(m);
        }
      }
      ChatHistoryDiagnostics.record(conversationID, {
        'event': 'local_snapshot',
        'count': safe.length,
        'elapsedMs': watch.elapsedMilliseconds,
      });
    } catch (_) {
      // This optional display read never fails the authoritative history load.
      ChatHistoryDiagnostics.record(conversationID, {
        'event': 'local_snapshot_unavailable',
        'elapsedMs': watch.elapsedMilliseconds,
      });
    }
  }

  void _syncHistoryState() {
    if (_closed) return;
    initialHistoryLoading.value = !_history.loaded && _history.loading;
    historyLoading.value = _history.loading;
    historyPagingLoading.value = _history.pagingLoading;
    historyError.value = _history.error?.toString();
    historyHasMore.value = _history.hasMore;
    historyScanLimited.value = _history.scanLimited;
    viewingHistory.value = _history.viewingHistory;
    if (!_history.viewingHistory) latestDeferred.value = false;
    newerHasMore.value = _history.hasNewer;
    windowRevision.value = _history.windowRevision;
  }

  void _replaceHistory(List<Message> messages, bool firstPage, bool refresh) {
    if (_closed) return;
    _snapshotIDs.clear();
    // Retain the last observed live edge when installing an older date window.
    _rememberRecoveryAnchor(messageList);
    _rememberRecoveryAnchor(messages);
    final offset = captureOffset();
    final alreadyPainted = _hasPaintedRows;
    final window = _history.currentWindow;
    final awaitingInitial = !hasPublishableWindow && window?.canPublish == true;
    final buffered = awaitingInitial
        ? messages.where((m) => (m.seq ?? 0) > window!.targetWatermark).toList()
        : <Message>[];
    messageList.value = messages
        .where(
            (m) => !awaitingInitial || (m.seq ?? 0) <= window!.targetWatermark)
        .map((m) => ChatHistoryCache.applyRevocation(accountID, m))
        .toList();
    if (window?.canPublish == true) {
      _publishedWindow = window;
      _ingress.accept(window!);
      for (final m in buffered) {
        _ingress.receive(m);
      }
    }
    if (hasPublishableWindow || canPaintInitialWindow?.call() != false) {
      initialWindowReady.value = true;
    }
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
    if (firstPage && !_history.viewingHistory && !alreadyPainted) {
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
    if (_ingress.receive(message)) return;
    _appendIncomingDirect(message, trim: trim);
  }

  void _appendWindowBatch(List<Message> batch) {
    if (_closed) return;
    final visible = batch
        .where((m) =>
            !removedIDs.contains(m.clientMsgID) &&
            m.status != MessageStatus.deleted &&
            !containsMessage(m.clientMsgID))
        .toList();
    if (visible.isEmpty) return;
    for (final row in visible) {
      _rememberRecoveryAnchor([row]);
    }
    // Both confirmed segments are already ordered; pending sends remain a
    // separate stable tail. Do not re-sort hundreds of unchanged bubbles.
    var next = <Message>[
      ...messageList.where((m) => (m.seq ?? 0) > 0),
      ...visible,
      ...messageList.where((m) => (m.seq ?? 0) <= 0),
    ];
    if (preserveReading?.call() != true &&
        !_history.viewingHistory &&
        next.length > automaticWindowLimit) {
      final start = next.length - automaticWindowLimit;
      next = [
        for (var i = 0; i < next.length; i++)
          if (i >= start ||
              next[i].status == MessageStatus.sending ||
              next[i].status == MessageStatus.failed)
            next[i]
      ];
      _history.didTrimLatest();
    }
    messageList.value = next
        .map((m) => ChatHistoryCache.applyRevocation(accountID, m))
        .toList();
  }

  void _appendIncomingDirect(Message message, {required bool trim}) {
    _snapshotIDs.remove(message.clientMsgID);
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
    _ingress.remove(id);
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
    _hasPaintedRows = false;
    _publishedWindow = null;
    _ingress.reset();
    latestDeferred.value = false;
    _snapshotIDs.clear();
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
    _ingress.close();
    _history.close();
    _messageListWorker?.dispose();
    _identities.clear();
    _cacheTimer?.cancel();
  }
}
