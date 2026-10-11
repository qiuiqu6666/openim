import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

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
  final bool Function() isActive;
  final void Function(List<ConversationInfo>) publish;
  final void Function() flushChanges;
  final Future<String> Function(ConversationRefreshRequest) _resolveID;
  final Future<List<ConversationInfo>> Function(List<String>) _read;
  final _pending = <String, ConversationRefreshRequest>{};
  // Only IDs in the in-flight read need a fence; no growing revision cache.
  final _changedDuringRead = <String>{};
  Timer? _timer;
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
    if (request != null) requestRefresh(request);
  }

  void requestRefresh(ConversationRefreshRequest request) {
    if (!_active || !request.isCurrent) return;
    _pending[request.key] = request;
    _schedule();
  }

  void conversationsChanged(Iterable<String> ids) {
    if (_running) _changedDuringRead.addAll(ids);
  }

  void discard(ConversationInfo info) {
    _pending.removeWhere((_, request) =>
        request.conversationID == info.conversationID ||
        (request.sessionType == info.conversationType &&
            request.sourceID ==
                (info.isSingleChat ? info.userID : info.groupID)));
    conversationsChanged([info.conversationID]);
  }

  void _schedule() {
    if (!_active || _running || _pending.isEmpty) return;
    _timer ??= Timer(settleDelay, () => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    _timer = null;
    if (!_active) return;
    final generation = _generation;
    final requests = _pending.values.take(_batchSize).toList();
    for (final request in requests) {
      _pending.remove(request.key);
    }
    _changedDuringRead.clear();
    _running = true;
    bool current() => _active && generation == _generation;
    try {
      final resolved = await Future.wait(requests.map((request) async {
        if (!current() || !request.isCurrent) return '';
        try {
          return await _resolveID(request).timeout(_queryTimeout);
        } catch (_) {
          // A later message/return/reconnect can retry; never poll on failure.
          return '';
        }
      }));
      final ids = resolved.where((id) => id.isNotEmpty).toSet();
      if (!current() ||
          ids.isEmpty ||
          requests.any((request) => !request.isCurrent)) {
        return;
      }
      final rows = await _read(ids.toList()).timeout(_queryTimeout);
      if (!current() || requests.any((request) => !request.isCurrent)) return;
      // Publish any buffered callback before applying the query snapshot.
      flushChanges();
      publish(rows
          .where((row) =>
              ids.contains(row.conversationID) &&
              !_changedDuringRead.contains(row.conversationID))
          .toList());
    } catch (error) {
      if (current()) {
        Logger.print(
            'Conversation latest refresh failed: ${error.runtimeType}');
      }
    } finally {
      if (generation == _generation) {
        _running = false;
        _changedDuringRead.clear();
        _schedule();
      }
    }
  }

  void reset() {
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
    _changedDuringRead.clear();
    _running = false;
  }

  void close() {
    _closed = true;
    reset();
  }
}
