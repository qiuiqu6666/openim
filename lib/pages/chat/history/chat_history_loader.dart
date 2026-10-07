import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

typedef ChatHistoryReader = Future<AdvancedMessage> Function(
    {required int count, Message? startMsg});

/// Coordinates the SDK's first page, older pages and refreshes for one route.
/// The route retains ownership of its existing observable message list.
class ChatHistoryLoader {
  ChatHistoryLoader({
    required this.fetch,
    this.fetchNewer,
    required this.messages,
    required this.replace,
    required this.removedIDs,
    required this.onStateChanged,
    this.onLoaded,
    this.preserveReading,
    this.pageSize = 40,
  });

  final ChatHistoryReader fetch;
  final ChatHistoryReader? fetchNewer;
  final List<Message> Function() messages;
  final void Function(List<Message>, bool firstPage, bool refresh) replace;
  final Set<String> removedIDs;
  final void Function() onStateChanged;
  final void Function()? onLoaded;
  final bool Function()? preserveReading;
  final int pageSize;

  bool loading = false;
  bool loaded = false;
  bool hasMore = true;
  bool viewingHistory = false;
  bool hasNewer = false;
  Object? error;
  bool _closed = false;
  bool _windowViewingHistory = false;
  bool _changingWindow = false;
  bool _windowRetry = false;
  int _generation = 0;
  int get windowRevision => _generation;
  Message? _cursor;
  Message? _latestAnchor;
  Message? _newerCursor;
  final _historicalIDs = <String?>{};
  Future<bool>? _request;
  Future<bool>? _queuedRefresh;
  Future<bool> Function()? _retry;

  Future<bool> retry() => _retry?.call() ?? loadOlder();

  bool holdCurrentWindow() {
    if (_closed || fetchNewer == null || viewingHistory) return viewingHistory;
    final persisted =
        messages().where((m) => !_isPendingSend(m.status)).toList();
    if (persisted.isEmpty) return false;
    _historicalIDs
      ..clear()
      ..addAll(persisted.map((m) => m.clientMsgID));
    _cursor ??= persisted.first;
    _newerCursor = persisted.last;
    viewingHistory = _windowViewingHistory = hasNewer = true;
    onStateChanged();
    return true;
  }

  /// Automatic latest-window eviction only changes the paging boundary.
  void didTrimLatest() {
    if (_closed || viewingHistory) return;
    _cursor = messages().where((m) => !_isPendingSend(m.status)).firstOrNull;
    hasMore = true;
    onStateChanged();
  }

  Future<bool> loadOlder() {
    if (_closed) return Future.value(false);
    if (_queuedRefresh != null) return _queuedRefresh!;
    if (_request != null) return _request!;
    if (loaded && !hasMore) return Future.value(false);
    return _start(refresh: false);
  }

  /// A sync/resume refresh waits for the current page and is coalesced.
  Future<bool> refresh() {
    if (_closed) return Future.value(false);
    // Live events, receipts and deletions keep a historical window current.
    // A latest-page refresh here would join two unrelated message ranges.
    if (viewingHistory) return Future.value(hasMore);
    if (_queuedRefresh != null) return _queuedRefresh!;
    if (_request == null) return _start(refresh: true);
    final pending = _request!;
    final generation = _generation;
    final completer = Completer<bool>();
    _queuedRefresh = completer.future;
    pending.then((_) async {
      if (_closed || generation != _generation) {
        completer.complete(false);
      } else {
        completer.complete(await _start(refresh: true));
      }
      if (identical(_queuedRefresh, completer.future)) _queuedRefresh = null;
    });
    return completer.future;
  }

  Future<bool> _start({required bool refresh}) {
    _windowRetry = false;
    _retry = refresh ? this.refresh : loadOlder;
    return _begin(() => _run(refresh: refresh));
  }

  Future<bool> _begin(Future<bool> Function() run) {
    final completer = Completer<bool>();
    _request = completer.future;
    loading = true;
    error = null;
    onStateChanged();
    run().then((result) {
      // A seek or clear can replace the owner while its SDK call is in flight.
      if (identical(_request, completer.future)) {
        if (_changingWindow && result && error == null) {
          _retry = null;
          _windowRetry = false;
        }
        _request = null;
        _changingWindow = false;
        loading = false;
        if (!_closed) onStateChanged();
      }
      completer.complete(result);
    });
    return completer.future;
  }

  /// Install one bounded, contiguous SDK range around the selected message.
  /// Seeking supersedes earlier requests rather than waiting for their pages.
  Future<bool> jumpTo(Message target) {
    if (_closed || removedIDs.contains(target.clientMsgID)) {
      return Future.value(false);
    }
    final newer = fetchNewer;
    if (newer == null) return Future.value(false);
    final previousHistory = _windowViewingHistory;
    _invalidate();
    viewingHistory = true;
    _changingWindow = true;
    _windowRetry = true;
    _retry = () => jumpTo(target);
    return _begin(() => _seek(target, newer, previousHistory));
  }

  Future<bool> _seek(
      Message target, ChatHistoryReader newer, bool previousHistory) async {
    final generation = _generation;
    final before = _HistorySnapshot(messages());
    try {
      final count = (pageSize / 2).ceil().clamp(1, pageSize);
      final pages = await Future.wait([
        fetch(count: count, startMsg: target),
        newer(count: count, startMsg: target),
      ]);
      if (_closed || generation != _generation) return false;
      if (removedIDs.contains(target.clientMsgID)) {
        viewingHistory = previousHistory;
        return false;
      }
      final olderPage =
          merge(pages[0].messageList ?? [], removedIDs: removedIDs);
      final newerPage =
          merge(pages[1].messageList ?? [], removedIDs: removedIDs);
      final page =
          merge([...olderPage, target, ...newerPage], removedIDs: removedIDs);
      final combined = merge(
          [..._reconcile(page, before), ..._pending(before, page)],
          removedIDs: removedIDs);
      _cursor = olderPage.firstOrNull ?? target;
      _newerCursor = newerPage.lastOrNull ?? target;
      _historicalIDs
        ..clear()
        ..addAll(page.map((m) => m.clientMsgID));
      hasMore = pages[0].isEnd != true;
      hasNewer = pages[1].isEnd != true;
      viewingHistory = hasNewer;
      _windowViewingHistory = viewingHistory;
      loaded = true;
      _latestAnchor = hasNewer ? null : _newerCursor;
      replace(combined, true, false);
      onLoaded?.call();
      return true;
    } catch (failure) {
      if (!_closed && generation == _generation) {
        viewingHistory = previousHistory;
        error = failure;
      }
      return false;
    }
  }

  Future<bool> loadNewer() {
    if (_closed || !viewingHistory || !hasNewer || fetchNewer == null) {
      return Future.value(false);
    }
    if (_request != null) return _request!;
    _windowRetry = false;
    _retry = loadNewer;
    return _begin(_runNewer);
  }

  Future<bool> _runNewer() async {
    final generation = _generation;
    final before = _HistorySnapshot(messages());
    try {
      if (_newerCursor == null ||
          removedIDs.contains(_newerCursor!.clientMsgID) ||
          !before.ids.contains(_newerCursor!.clientMsgID)) {
        _newerCursor = messages()
            .where((m) =>
                !removedIDs.contains(m.clientMsgID) &&
                _historicalIDs.contains(m.clientMsgID) &&
                !_isPendingSend(m.status))
            .lastOrNull;
      }
      if (_newerCursor == null) return false;
      final result = await fetchNewer!(count: pageSize, startMsg: _newerCursor);
      if (_closed || generation != _generation) return false;
      final page = merge(result.messageList ?? [], removedIDs: removedIDs);
      _historicalIDs.addAll(page.map((m) => m.clientMsgID));
      final combined = merge([...messages(), ..._reconcile(page, before)],
          removedIDs: removedIDs);
      _newerCursor = page.lastOrNull ?? _newerCursor;
      hasNewer = result.isEnd != true;
      if (!hasNewer) {
        viewingHistory = false;
        _windowViewingHistory = false;
        _historicalIDs.clear();
        _latestAnchor = _newerCursor;
      }
      replace(combined, false, false);
      return hasNewer;
    } catch (failure) {
      if (!_closed && generation == _generation) error = failure;
      return hasNewer;
    }
  }

  /// Fetch the latest contiguous window before leaving historical mode.
  Future<bool> returnToLatest() {
    if (_closed) return Future.value(false);
    _invalidate();
    viewingHistory = _windowViewingHistory;
    _changingWindow = true;
    _windowRetry = true;
    _retry = returnToLatest;
    return _begin(() => _run(refresh: true, latest: true));
  }

  /// User scrolling cancels a pending or failed window replacement, keeping its
  /// installed messages and cursors. Ordinary paging/retries remain unaffected.
  void cancelWindowChange() {
    if (_closed || (!_changingWindow && !(_windowRetry && _request == null))) {
      return;
    }
    _invalidate();
    viewingHistory = _windowViewingHistory;
    loading = false;
    error = null;
    _retry = null;
    _windowRetry = false;
    onStateChanged();
  }

  Future<bool> _run({required bool refresh, bool latest = false}) async {
    final generation = _generation;
    final firstPage = !loaded || latest;
    final before = List<Message>.of(messages());
    final snapshot = _HistorySnapshot(before);
    final beforeIDs = snapshot.ids;
    try {
      if (!firstPage &&
          !refresh &&
          _cursor != null &&
          (removedIDs.contains(_cursor!.clientMsgID) ||
              !beforeIDs.contains(_cursor!.clientMsgID))) {
        _cursor = before
            .where((m) =>
                !removedIDs.contains(m.clientMsgID) &&
                (!_windowViewingHistory ||
                    _historicalIDs.contains(m.clientMsgID)) &&
                m.status != MessageStatus.sending &&
                m.status != MessageStatus.failed)
            .firstOrNull;
      }
      if (!firstPage && !refresh && viewingHistory && _cursor == null) {
        hasMore = false;
        return false;
      }
      final result = await fetch(
          count: pageSize, startMsg: firstPage || refresh ? null : _cursor);
      if (_closed || generation != _generation) return false;
      final page = result.messageList ?? <Message>[];
      if (_windowViewingHistory && !latest) {
        _historicalIDs.addAll(page.map((m) => m.clientMsgID));
      }
      final current = messages();
      // Keep messages received/sent while the request was outstanding.
      final arrived = current.where((m) => !beforeIDs.contains(m.clientMsgID));
      final pending = _pending(snapshot, page);
      // A burst larger than one page can leave a gap between this latest page
      // and the old window. Page from the new boundary to keep history reachable.
      final discontinuous = refresh &&
          !firstPage &&
          page.isNotEmpty &&
          result.isEnd != true &&
          _latestAnchor != null &&
          _compare(page.first, _latestAnchor!) > 0;
      if (discontinuous &&
          !latest &&
          preserveReading?.call() == true &&
          fetchNewer != null &&
          holdCurrentWindow()) {
        // Keep the painted range. The user can page toward the new messages
        // or explicitly return to latest without joining two disjoint ranges.
        return hasMore;
      }
      Iterable<Message> retained;
      if (firstPage) {
        retained = const <Message>[];
      } else if (!refresh) {
        retained = current;
      } else if (result.isEnd == true || discontinuous) {
        retained = const <Message>[];
      } else if (page.isEmpty) {
        retained = current;
      } else {
        // The refreshed latest page is authoritative for its covered range.
        // Older, already paged history and its cursor remain in place.
        final oldest = page.first;
        retained = current.where((m) => _compare(m, oldest) < 0);
      }
      final reconciled = _reconcile(page, snapshot);
      final combined = merge(
          [...retained, ...reconciled, ...pending, ...arrived],
          removedIDs: removedIDs);
      final pageCursor =
          page.where((m) => !removedIDs.contains(m.clientMsgID)).firstOrNull;
      if (firstPage || !refresh || discontinuous) {
        if (pageCursor != null) _cursor = pageCursor;
        hasMore = page.isNotEmpty && result.isEnd != true;
      } else if (_cursor == null) {
        hasMore = page.isNotEmpty && result.isEnd != true;
        _cursor = pageCursor;
      } else if (result.isEnd == true) {
        hasMore = false;
        _cursor = pageCursor;
      }
      loaded = true;
      if (latest) {
        viewingHistory = false;
        _windowViewingHistory = false;
        _historicalIDs.clear();
        hasNewer = false;
        _newerCursor = null;
      }
      if (firstPage || refresh) _latestAnchor = page.lastOrNull;
      replace(combined, firstPage || discontinuous, refresh);
      onLoaded?.call();
      return latest ? true : hasMore;
    } catch (failure) {
      if (!_closed && generation == _generation) error = failure;
      return latest ? false : hasMore;
    }
  }

  Iterable<Message> _pending(_HistorySnapshot before, List<Message> page) {
    final pageIDs = page.map((m) => m.clientMsgID).toSet();
    return messages().where((m) =>
        !pageIDs.contains(m.clientMsgID) &&
        (_isPendingSend(m.status) ||
            (_isPendingSend(before.status[m.clientMsgID]) &&
                m.status == MessageStatus.succeeded)));
  }

  List<Message> _reconcile(List<Message> page, _HistorySnapshot before) {
    final localByID = {for (final m in messages()) m.clientMsgID: m};
    final reconciled = <Message>[];
    for (final fresh in page) {
      final local = localByID[fresh.clientMsgID];
      // Do not undo receipts or voice metadata received while awaiting the SDK.
      if (local?.isRead == true) {
        fresh.isRead = true;
        fresh.hasReadTime = local!.hasReadTime;
      }
      if (local != null && local.localEx != before.localEx[fresh.clientMsgID]) {
        fresh.localEx = local.localEx;
      }
      final statusChanged = local != null &&
          before.status.containsKey(fresh.clientMsgID) &&
          local.status != before.status[fresh.clientMsgID];
      if (local != null &&
          _isPendingSend(fresh.status) &&
          (local.status == MessageStatus.succeeded || statusChanged)) {
        if (fresh.isRead == true) {
          local.isRead = true;
          local.hasReadTime = fresh.hasReadTime;
        }
        local.localEx = fresh.localEx;
        reconciled.add(local);
      } else if (local != null &&
          (_isPendingSend(local.status) ||
              _isPendingSend(before.status[fresh.clientMsgID]))) {
        // Send callbacks retain this object; accept confirmed SDK fields in it.
        local.update(fresh);
        local.localEx = fresh.localEx;
        reconciled.add(local);
      } else {
        reconciled.add(fresh);
      }
    }
    return reconciled;
  }

  static bool _isPendingSend(int? status) =>
      status == MessageStatus.sending || status == MessageStatus.failed;

  static int _compare(Message a, Message b) {
    final time = (a.sendTime ?? a.createTime ?? 0)
        .compareTo(b.sendTime ?? b.createTime ?? 0);
    return time != 0 ? time : (a.seq ?? 0).compareTo(b.seq ?? 0);
  }

  static List<Message> merge(Iterable<Message> values,
      {Set<String> removedIDs = const {}}) {
    final unique = <Object, Message>{};
    for (final message in values) {
      final id = message.clientMsgID;
      if (id != null && removedIDs.contains(id)) continue;
      unique[id ?? message] = message;
    }
    return unique.values.toList()..sort(_compare);
  }

  void close() {
    _closed = true;
    _invalidate();
    _retry = null;
    _windowRetry = false;
    loading = false;
  }

  void _invalidate() {
    _generation++;
    _request = null;
    _queuedRefresh = null;
    _changingWindow = false;
  }

  /// The SDK has cleared the conversation. Discard all older query results,
  /// including refreshes queued before that operation completed.
  void clear() {
    _invalidate();
    _retry = null;
    _windowRetry = false;
    _cursor = null;
    _latestAnchor = null;
    _newerCursor = null;
    _historicalIDs.clear();
    loaded = true;
    loading = false;
    hasMore = false;
    hasNewer = false;
    viewingHistory = false;
    _windowViewingHistory = false;
    error = null;
    if (!_closed) onStateChanged();
  }
}

/// Message instances are mutable send-callback targets. Capture their values
/// before awaiting a query so newer local state can win over its SDK snapshot.
class _HistorySnapshot {
  _HistorySnapshot(List<Message> messages)
      : ids = messages.map((m) => m.clientMsgID).toSet(),
        localEx = {for (final m in messages) m.clientMsgID: m.localEx},
        status = {for (final m in messages) m.clientMsgID: m.status};

  final Set<String?> ids;
  final Map<String?, String?> localEx;
  final Map<String?, int?> status;
}
