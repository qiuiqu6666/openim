import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import '../../../core/session/queries/sdk_query_gate.dart';

/// Repairs missing conversation callbacks using the SDK's local snapshot.
/// Bursts are batched; a query cannot overwrite a callback received during it.
class ConversationLatestSync {
  ConversationLatestSync({
    required this.isActive,
    required this.publish,
    required this.flushChanges,
    Future<String> Function(ConversationRefreshRequest)? resolveID,
    Future<List<ConversationInfo>> Function(List<String>)? read,
  })  : _resolveID = resolveID ?? _sdkID,
        _read = read ?? _sdkRead;

  static const settleDelay = Duration(milliseconds: 120);
  static const _queryTimeout = Duration(seconds: 5);
  static const _batchSize = 64;
  static const _retryDelay = Duration(seconds: 1);
  static const _maxRetries = 2;
  final bool Function() isActive;
  final void Function(List<ConversationInfo>) publish;
  final void Function() flushChanges;
  final Future<String> Function(ConversationRefreshRequest) _resolveID;
  final Future<List<ConversationInfo>> Function(List<String>) _read;
  final _reads = SdkQueryGate<List<ConversationInfo>>();
  final _ids = SdkQueryGate<String>(limit: 4);
  final _pending = <String, ConversationRefreshRequest>{};
  final _pendingMessageIDs = <String, String>{};
  final _callbackMessages = <String, String>{};
  final _forced = <String>{};
  final _pendingAttempts = <String, int>{};
  final _retries = <String, _LatestSyncAttempt>{};
  // Only IDs in the in-flight read need a fence; no growing revision cache.
  final _changedDuringRead = <String>{};
  final _discardedDuringRead = <String>{};
  Timer? _timer;
  Timer? _retryTimer;
  bool _running = false, _closed = false;
  int _generation = 0;
  bool get _active => !_closed && isActive();

  static Future<String> _sdkID(ConversationRefreshRequest request) async =>
      request.conversationID ??
      await OpenIM.iMManager.conversationManager.getConversationIDBySessionType(
          sourceID: request.sourceID!, sessionType: request.sessionType!);

  static Future<List<ConversationInfo>> _sdkRead(List<String> ids) =>
      OpenIM.iMManager.conversationManager
          .getMultipleConversation(conversationIDList: ids);

  void observeMessage(Message message) {
    final request = ConversationRefreshRequest.forMessage(message);
    if (request == null || !_active || !request.isCurrent) return;
    final id = message.clientMsgID;
    if (id != null && _callbackMessages[request.key] == id) return;
    _forgetRetry(request.key);
    if (id != null) _pendingMessageIDs[request.key] = id;
    _pending[request.key] = request;
    _schedule();
  }

  void requestRefresh(ConversationRefreshRequest request) {
    if (!_active || !request.isCurrent) return;
    _forgetRetry(request.key);
    _pending[request.key] = request;
    _forced.add(request.key);
    _schedule();
  }

  void conversationsChanged(Iterable<String> ids) {
    if (_running) _changedDuringRead.addAll(ids);
  }

  /// A matching authoritative callback already supplies this message's row.
  void conversationsUpdated(Iterable<ConversationInfo> rows) {
    for (final row in rows) {
      final id = row.latestMsg?.clientMsgID;
      if (id == null || id.isEmpty) continue;
      final source = row.isSingleChat ? row.userID : row.groupID;
      for (final key in [
        row.conversationID,
        '${row.conversationType}:$source'
      ]) {
        _callbackMessages.remove(key);
        _callbackMessages[key] = id;
        if (!_forced.contains(key) && _pendingMessageIDs[key] == id) {
          _pending.remove(key);
          _pendingMessageIDs.remove(key);
          _pendingAttempts.remove(key);
        }
        final retry = _retries[key];
        if (retry != null && !retry.forced && retry.messageID == id) {
          _forgetRetry(key);
        }
      }
    }
    while (_callbackMessages.length > 256) {
      _callbackMessages.remove(_callbackMessages.keys.first);
    }
  }

  void discard(ConversationInfo info) {
    final keys = [
      info.conversationID,
      '${info.conversationType}:${info.isSingleChat ? info.userID : info.groupID}'
    ];
    for (final key in keys) {
      _pending.remove(key);
      _pendingMessageIDs.remove(key);
      _forced.remove(key);
      _callbackMessages.remove(key);
      _forgetRetry(key);
      if (_running) _discardedDuringRead.add(key);
    }
    conversationsChanged([info.conversationID]);
  }

  void _schedule() {
    if (!_active || _running || _pending.isEmpty) return;
    _timer ??= Timer(settleDelay, () => unawaited(_refresh()));
  }

  void _forgetRetry(String key) {
    _pendingAttempts.remove(key);
    _retries.remove(key);
    if (_retries.isEmpty) {
      _retryTimer?.cancel();
      _retryTimer = null;
    }
  }

  void _retryLater(_LatestSyncAttempt attempt) {
    final request = attempt.request;
    if (!_active ||
        !request.isCurrent ||
        attempt.number >= _maxRetries ||
        _pending.containsKey(request.key) ||
        _discardedDuringRead.contains(request.key) ||
        _changedDuringRead.contains(attempt.conversationID) ||
        (!attempt.forced &&
            attempt.messageID != null &&
            _callbackMessages[request.key] == attempt.messageID)) {
      return;
    }
    _retries[request.key] = attempt;
    _retryTimer ??= Timer(_retryDelay, () {
      _retryTimer = null;
      final retries = _retries.values.toList();
      _retries.clear();
      if (!_active) return;
      for (final retry in retries) {
        final request = retry.request;
        if (!request.isCurrent || _pending.containsKey(request.key)) continue;
        _pending[request.key] = request;
        _pendingAttempts[request.key] = retry.number + 1;
        if (retry.messageID != null) {
          _pendingMessageIDs[request.key] = retry.messageID!;
        }
        if (retry.forced) _forced.add(request.key);
      }
      _schedule();
    });
  }

  Future<void> _refresh() async {
    _timer = null;
    if (!_active) return;
    final generation = _generation;
    final attempts = _pending.values
        .take(_batchSize)
        .map((request) => _LatestSyncAttempt(request,
            messageID: _pendingMessageIDs[request.key],
            forced: _forced.contains(request.key),
            number: _pendingAttempts[request.key] ?? 0))
        .toList();
    for (final attempt in attempts) {
      final request = attempt.request;
      _pending.remove(request.key);
      _pendingMessageIDs.remove(request.key);
      _forced.remove(request.key);
      _pendingAttempts.remove(request.key);
    }
    _changedDuringRead.clear();
    _discardedDuringRead.clear();
    _running = true;
    bool current() => _active && generation == _generation;
    try {
      final resolved = await Future.wait(attempts.map((attempt) async {
        final request = attempt.request;
        if (!current() || !request.isCurrent) return '';
        try {
          final id = await _ids.run(
              (generation, request.key), () => _resolveID(request),
              timeout: _queryTimeout,
              isCurrent: () => current() && request.isCurrent);
          attempt.conversationID = id;
          return id;
        } catch (_) {
          if (current()) _retryLater(attempt);
          return '';
        }
      }));
      final ids = resolved.where((id) => id.isNotEmpty).toSet();
      if (!current() ||
          ids.isEmpty ||
          attempts.any((attempt) => !attempt.request.isCurrent)) {
        return;
      }
      // A new attempt may wait for a timed-out read, but cannot publish its
      // stale result or start another native read while it still owns a slot.
      final rows = await _reads.run(Object(), () => _read(ids.toList()),
          timeout: _queryTimeout, isCurrent: current);
      if (!current() || attempts.any((attempt) => !attempt.request.isCurrent)) {
        return;
      }
      // Publish any buffered callback before applying the query snapshot.
      flushChanges();
      publish(rows
          .where((row) =>
              ids.contains(row.conversationID) &&
              !_changedDuringRead.contains(row.conversationID))
          .toList());
    } catch (error) {
      if (current()) {
        for (final attempt in attempts) {
          _retryLater(attempt);
        }
        Logger.print(
            'Conversation latest refresh failed: ${error.runtimeType}');
      }
    } finally {
      if (generation == _generation) {
        _running = false;
        _changedDuringRead.clear();
        _discardedDuringRead.clear();
        _schedule();
      }
    }
  }

  void reset() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retries.clear();
    _pendingAttempts.clear();
    _pending.clear();
    _pendingMessageIDs.clear();
    _callbackMessages.clear();
    _forced.clear();
    _changedDuringRead.clear();
    _discardedDuringRead.clear();
    _running = false;
  }

  void close() {
    _closed = true;
    _reads.close();
    _ids.close();
    reset();
  }
}

class _LatestSyncAttempt {
  _LatestSyncAttempt(this.request,
      {required this.messageID, required this.forced, required this.number})
      : conversationID = request.conversationID;

  final ConversationRefreshRequest request;
  final String? messageID;
  final bool forced;
  final int number;
  String? conversationID;
}
