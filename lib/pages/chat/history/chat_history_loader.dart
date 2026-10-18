import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'chat_history_read_gate.dart';
import 'chat_history_window.dart';
import 'chat_history_diagnostics.dart';
import '../history_search/context/search_chat_window.dart';

export 'chat_history_read_gate.dart' show ChatHistoryReader;

/// Coordinates the SDK's first page, older pages and refreshes for one route.
/// The route retains ownership of its existing observable message list.
class ChatHistoryLoader {
  MessageWindow? currentWindow;
  ChatHistoryLoader({
    required this.fetch,
    this.fetchNewer,
    this.isDisplaySnapshot,
    this.hasPaintedRows,
    this.expectsLatest,
    this.onLatestDeferred,
    this.beforeLatestReplace,
    required this.messages,
    required this.replace,
    required this.removedIDs,
    required this.onStateChanged,
    this.onLoaded,
    this.preserveReading,
    this.canTrimHistory,
    this.pageSize = 40,
    this.diagnostic,
    Duration readTimeout = const Duration(seconds: 30),
  }) : _reads = ChatHistoryReadGate(timeout: readTimeout);

  final ChatHistoryReader fetch;
  final ChatHistoryReader? fetchNewer;
  final bool Function(String?)? isDisplaySnapshot;
  final bool Function()? hasPaintedRows;
  final bool Function()? expectsLatest;
  final void Function()? onLatestDeferred;
  final Future<void> Function()? beforeLatestReplace;
  final List<Message> Function() messages;
  final void Function(List<Message>, bool firstPage, bool refresh) replace;
  final Set<String> removedIDs;
  final void Function() onStateChanged;
  final void Function()? onLoaded;
  final bool Function()? preserveReading;
  final bool Function(bool older)? canTrimHistory;
  final int pageSize;
  final HistoryDiagnostic? diagnostic;
  final ChatHistoryReadGate _reads;
  SearchChatWindow? _searchWindow;

  bool loading = false;
  bool _backgroundRefresh = false;

  /// Keep refresh reads busy for coordination without adding a paging row.
  bool get pagingLoading => loading && !_backgroundRefresh;
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
  HistoryScanCursor? _olderScan, _newerScan;
  bool get scanLimited => _olderScan != null || _newerScan != null;
  final _historicalIDs = <String?>{};
  Future<bool>? _request;
  Future<bool>? _queuedRefresh;
  Future<bool> Function()? _retry;

  Future<bool> retry() => _olderScan != null
      ? loadOlder()
      : _newerScan != null
          ? loadNewer()
          : _retry?.call() ?? loadOlder();

  /// Recovery shares the native read limit but does not move the reading
  /// window's older/newer cursors or replace its visible rows.
  Future<AdvancedMessage> readNewerForRecovery(
      {required int count, Message? startMsg}) {
    final reader = fetchNewer;
    if (_closed || reader == null) {
      return Future.error(StateError('Chat history is unavailable'));
    }
    return _reads.read(reader,
        count: count, startMsg: startMsg, revision: _generation);
  }

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
    // A yielded scan belongs to explicit continuation. Sync notifications must
    // neither restart at latest nor keep scanning a long deleted range.
    if (scanLimited) {
      diagnostic?.call({
        'event': 'refresh_skipped',
        'reason': 'scan_paused',
        'revision': _generation,
        'scanSeq': _olderScan?.seq ?? _newerScan?.seq
      });
      return Future.value(hasMore);
    }
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
      // This refresh is starting now. A sync signal received after its SDK
      // snapshot starts must be able to queue one subsequent, fresher read.
      if (identical(_queuedRefresh, completer.future)) _queuedRefresh = null;
      if (_closed || generation != _generation) {
        completer.complete(false);
      } else {
        completer.complete(await _start(refresh: true));
      }
    });
    return completer.future;
  }

  Future<bool> _start({required bool refresh}) {
    _windowRetry = false;
    _retry = refresh ? this.refresh : loadOlder;
    return _begin(() => _run(refresh: refresh),
        backgroundRefresh: refresh && loaded);
  }

  Future<bool> _begin(Future<bool> Function() run,
      {bool backgroundRefresh = false}) {
    final completer = Completer<bool>();
    _request = completer.future;
    loading = true;
    _backgroundRefresh = backgroundRefresh;
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
      final cloud = target is SearchChatTarget ? target.window : null;
      final pages = cloud != null
          ? [
              AdvancedMessage(
                  messageList: cloud.initial.messages
                      .where((m) => m.seq! < target.seq!)
                      .toList(),
                  isEnd: cloud.initial.beforeEnd),
              AdvancedMessage(
                  messageList: cloud.initial.messages
                      .where((m) => m.seq! > target.seq!)
                      .toList(),
                  isEnd: cloud.initial.afterEnd),
            ]
          : await Future.wait([
              _reads.read(fetch,
                  count: count, startMsg: target, revision: generation),
              _reads.read(newer,
                  count: count, startMsg: target, revision: generation),
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
      _olderScan = pages[0].scanCursor;
      _newerScan = pages[1].scanCursor;
      _cursor = olderPage.firstOrNull ?? target;
      _newerCursor = newerPage.lastOrNull ?? target;
      _historicalIDs
        ..clear()
        ..addAll(page.map((m) => m.clientMsgID));
      hasMore = pages[0].isEnd != true;
      hasNewer = pages[1].isEnd != true;
      viewingHistory = cloud != null || hasNewer;
      _windowViewingHistory = viewingHistory;
      loaded = true;
      _searchWindow = cloud;
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
      if (_newerScan == null &&
          (_newerCursor == null ||
              removedIDs.contains(_newerCursor!.clientMsgID) ||
              !before.ids.contains(_newerCursor!.clientMsgID))) {
        _newerCursor = messages()
            .where((m) =>
                !removedIDs.contains(m.clientMsgID) &&
                _historicalIDs.contains(m.clientMsgID) &&
                !_isPendingSend(m.status))
            .lastOrNull;
      }
      if (_newerScan == null && _newerCursor == null) return false;
      diagnostic?.call({
        'event': 'request',
        'source': 'newer_page',
        'revision': generation,
        'cursor': (_newerScan ?? _newerCursor)?.clientMsgID,
        'scanSeq': _newerScan?.seq
      });
      final result = _searchWindow != null
          ? await _searchWindow!
              .read(false, () => !_closed && generation == _generation)
          : await _reads.read(fetchNewer!,
              count: pageSize,
              startMsg: _newerScan ?? _newerCursor,
              revision: generation);
      if (_closed || generation != _generation) return false;
      final page = merge(result.messageList ?? [], removedIDs: removedIDs);
      _historicalIDs.addAll(page.map((m) => m.clientMsgID));
      var combined = merge([...messages(), ..._reconcile(page, before)],
          removedIDs: removedIDs);
      _newerCursor = page.lastOrNull ?? _newerCursor;
      _newerScan = result.scanCursor;
      _recordPage(result, generation);
      hasNewer = result.isEnd != true;
      if (!hasNewer && _searchWindow == null) {
        viewingHistory = false;
        _windowViewingHistory = false;
        _historicalIDs.clear();
        _latestAnchor = _newerCursor;
      }
      if (_searchWindow == null && canTrimHistory?.call(false) == true) {
        final bounded = trimChatHistoryWindow(combined, older: false);
        if (bounded.length != combined.length) {
          combined = bounded;
          _cursor =
              combined.where((m) => !_isPendingSend(m.status)).firstOrNull;
          hasMore = true;
          if (viewingHistory) {
            _historicalIDs
              ..clear()
              ..addAll(combined
                  .where((m) => !_isPendingSend(m.status))
                  .map((m) => m.clientMsgID));
          }
        }
      }
      replace(combined, false, false);
      return hasNewer;
    } catch (failure) {
      diagnostic?.call({
        'event': 'failure',
        'source': 'newer_page',
        'revision': generation,
        'error': failure.toString()
      });
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
      diagnostic?.call({
        'event': 'request',
        'source': latest
            ? 'return_latest'
            : refresh
                ? 'refresh'
                : 'older_page',
        'revision': generation,
        'cursor': (_olderScan ?? (firstPage || refresh ? null : _cursor))
            ?.clientMsgID,
        'scanSeq': _olderScan?.seq
      });
      final result = _searchWindow != null && !latest && !refresh
          ? await _searchWindow!
              .read(true, () => !_closed && generation == _generation)
          : await _reads.read(fetch,
              count: pageSize,
              startMsg: _olderScan ?? (firstPage || refresh ? null : _cursor),
              revision: generation);
      if (_closed || generation != _generation) return false;
      _recordPage(result, generation);
      final page = result.messageList ?? <Message>[];
      if (result.window != null && !result.window!.canPublish) {
        throw StateError('Message window is not covered yet');
      }
      if (_windowViewingHistory && !latest) {
        _historicalIDs.addAll(page.map((m) => m.clientMsgID));
      }
      final current = messages();
      if (firstPage &&
          page.isEmpty &&
          result.window?.emptyConfirmed != true &&
          result.scanLimited != true &&
          (expectsLatest?.call() == true ||
              before
                  .followedBy(current.where(
                      (m) => isDisplaySnapshot?.call(m.clientMsgID) == true))
                  .any((m) =>
                      !removedIDs.contains(m.clientMsgID) &&
                      !_isPendingSend(m.status)))) {
        // A first-frame snapshot or historical window is still visible. Do
        // not confirm an empty replacement or enable read receipts from it;
        // the existing finite recovery owner can retry this same operation.
        throw StateError(
            'Latest history returned no messages for the visible window');
      }
      if (refresh &&
          !firstPage &&
          !latest &&
          page.isEmpty &&
          result.scanLimited != true) {
        // A resume query can race native recovery. Empty is not a deletion
        // receipt: preserve both the displayed window and its paging anchors.
        return hasMore;
      }
      // Keep messages received/sent while the request was outstanding.
      final arrived = current.where((m) =>
          !beforeIDs.contains(m.clientMsgID) &&
          isDisplaySnapshot?.call(m.clientMsgID) != true);
      final pending = _pending(snapshot, page);
      final visibleTail =
          current.where((m) => !_isPendingSend(m.status)).lastOrNull;
      if (!latest &&
          (firstPage || refresh) &&
          (firstPage || preserveReading?.call() == true) &&
          hasPaintedRows?.call() == true &&
          visibleTail != null &&
          page.isNotEmpty &&
          _compare(page.last, visibleTail) > 0 &&
          (result.window == null ||
              result.window!.lowerBound > (visibleTail.seq ?? 0) + 1) &&
          holdCurrentWindow()) {
        // Preserve an initial painted snapshot or an explicit history reader.
        // A loaded page following latest must install the new bounded window
        // after resume, rather than becoming stuck buffering every live event.
        loaded = true;
        hasMore = true;
        onLatestDeferred?.call();
        onLoaded?.call();
        return hasMore;
      }
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
        // Keep the first-frame snapshot until the bounded scan can establish
        // an authoritative range. Scan metadata never enters the message list.
        retained = page.isEmpty && result.scanLimited == true
            ? current
            : const <Message>[];
      } else if (!refresh) {
        retained = current;
      } else if (page.isEmpty) {
        // isEnd describes this query's pagination, not a deletion of rows
        // already displayed. Clear/delete events have their own generation
        // and removed-ID fences and remain authoritative.
        retained = current;
      } else if (result.isEnd == true || discontinuous) {
        retained = const <Message>[];
      } else {
        // The refreshed latest page is authoritative for its covered range.
        // Older, already paged history and its cursor remain in place.
        final oldest = page.first;
        retained = current.where((m) => _compare(m, oldest) < 0);
      }
      if (latest && beforeLatestReplace != null) {
        await beforeLatestReplace!();
        if (_closed || generation != _generation) return false;
      }
      final reconciled = _reconcile(page, snapshot);
      var combined = merge([...retained, ...reconciled, ...pending, ...arrived],
          removedIDs: removedIDs);
      final pageCursor =
          page.where((m) => !removedIDs.contains(m.clientMsgID)).firstOrNull;
      _olderScan = result.scanCursor;
      if (firstPage || !refresh || discontinuous) {
        if (pageCursor != null) _cursor = pageCursor;
        hasMore =
            (page.isNotEmpty || _olderScan != null) && result.isEnd != true;
      } else if (_cursor == null) {
        hasMore =
            (page.isNotEmpty || _olderScan != null) && result.isEnd != true;
        _cursor = pageCursor;
      } else if (result.isEnd == true) {
        hasMore = false;
        _cursor = pageCursor;
      }
      if (_olderScan != null) hasMore = true;
      loaded = true;
      if (latest) {
        _searchWindow = null;
        viewingHistory = false;
        _windowViewingHistory = false;
        _historicalIDs.clear();
        hasNewer = false;
        _newerCursor = null;
      }
      if (firstPage || refresh) _latestAnchor = page.lastOrNull;
      if (!firstPage &&
          !refresh &&
          _searchWindow == null &&
          fetchNewer != null &&
          canTrimHistory?.call(true) == true) {
        final bounded = trimChatHistoryWindow(combined, older: true);
        if (bounded.length != combined.length) {
          combined = bounded;
          final persisted = combined.where((m) => !_isPendingSend(m.status));
          _newerCursor = persisted.lastOrNull;
          _historicalIDs
            ..clear()
            ..addAll(persisted.map((m) => m.clientMsgID));
          viewingHistory = _windowViewingHistory = hasNewer = true;
        }
      }
      if (result.window != null) currentWindow = result.window;
      replace(combined, firstPage || discontinuous, refresh);
      onLoaded?.call();
      return latest ? true : hasMore;
    } catch (failure) {
      diagnostic?.call({
        'event': 'failure',
        'source': latest
            ? 'return_latest'
            : refresh
                ? 'refresh'
                : 'older_page',
        'revision': generation,
        'scanSeq': _olderScan?.seq,
        'error': failure.toString()
      });
      if (!_closed && generation == _generation) error = failure;
      return latest ? false : hasMore;
    }
  }

  void _recordPage(AdvancedMessage result, int revision) => diagnostic?.call({
        'event': 'result',
        'revision': revision,
        'visibleCount': result.messageList?.length ?? 0,
        'isEnd': result.isEnd,
        'scanLimited': result.scanLimited == true,
        'scanSeq': result.scanCursor?.seq,
        'scanCursor': result.scanCursor?.clientMsgID,
      });

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
      if (local?.contentType == MessageType.revokeMessageNotification &&
          fresh.contentType != MessageType.revokeMessageNotification) {
        reconciled.add(local!);
        continue;
      }
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
    if (_isLocalRecord(a) || _isLocalRecord(b)) {
      if (_isPendingSend(a.status)) return 1;
      if (_isPendingSend(b.status)) return -1;
      final time = (a.sendTime ?? a.createTime ?? 0)
          .compareTo(b.sendTime ?? b.createTime ?? 0);
      if (time != 0) return time;
    }
    if ((a.seq ?? 0) > 0 && (b.seq ?? 0) > 0) {
      return a.seq!.compareTo(b.seq!);
    }
    if ((a.seq ?? 0) > 0) return -1;
    if ((b.seq ?? 0) > 0) return 1;
    final time = (a.sendTime ?? a.createTime ?? 0)
        .compareTo(b.sendTime ?? b.createTime ?? 0);
    if (time != 0) return time;
    final aSequence = a.seq ?? 0;
    final bSequence = b.seq ?? 0;
    // An unsequenced live row is provisional, not older than every persisted
    // message in the same second. Keep it after the known sequence range.
    if (aSequence <= 0) return bSequence <= 0 ? 0 : 1;
    if (bSequence <= 0) return -1;
    return aSequence.compareTo(bSequence);
  }

  static int compareMessageOrder(Message a, Message b) => _compare(a, b);

  static bool _isLocalRecord(Message message) =>
      (message.seq ?? 0) == 0 && message.status == MessageStatus.succeeded;

  static List<Message> merge(Iterable<Message> values,
      {Set<String> removedIDs = const {}}) {
    final unique = <Object, Message>{};
    for (final message in values) {
      final id = message.clientMsgID;
      if (id != null && removedIDs.contains(id)) continue;
      unique[id ?? message] = message;
    }
    // List.sort is not stable. Preserve arrival order explicitly when neither
    // same-time row has a server sequence, including across history merges.
    // Server sequence and local wall-clock order are different domains.
    // Sort each separately to avoid a non-transitive mixed comparator when
    // server timestamps go backwards, then insert persisted local records.
    final indexed =
        unique.values.where((m) => !_isLocalRecord(m)).indexed.toList();
    indexed.sort((a, b) {
      final order = _compare(a.$2, b.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
    final result = indexed.map((entry) => entry.$2).toList();
    return _insertLocalRecords(result, unique.values.where(_isLocalRecord));
  }

  /// The ingress has already ordered and deduplicated the new server batch.
  /// Retain that order without sorting the full visible window on each event.
  static List<Message> appendOrderedBatch(
      Iterable<Message> current, List<Message> batch) {
    final confirmed = <Message>[];
    final provisional = <Message>[];
    final local = <Message>[];
    for (final message in current) {
      if (_isLocalRecord(message)) {
        local.add(message);
      } else if ((message.seq ?? 0) > 0) {
        confirmed.add(message);
      } else {
        provisional.add(message);
      }
    }
    return _insertLocalRecords([...confirmed, ...batch, ...provisional], local);
  }

  static List<Message> _insertLocalRecords(
      List<Message> result, Iterable<Message> records) {
    final local = records.indexed.toList();
    local.sort((a, b) {
      final order = _compare(a.$2, b.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
    for (final entry in local) {
      final at = result.indexWhere((m) => _compare(entry.$2, m) < 0);
      result.insert(at < 0 ? result.length : at, entry.$2);
    }
    return result;
  }

  void close() {
    _searchWindow = null;
    _closed = true;
    _reads.close();
    _invalidate();
    _retry = null;
    _windowRetry = false;
    loading = false;
  }

  void _invalidate() {
    _generation++;
    _reads.invalidate(_generation);
    _request = null;
    _queuedRefresh = null;
    _changingWindow = false;
    _olderScan = _newerScan = null;
  }

  /// The SDK has cleared the conversation. Discard all older query results,
  /// including refreshes queued before that operation completed.
  void clear() {
    _searchWindow = null;
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
