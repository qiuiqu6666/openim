import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

typedef ChatHistoryReader = Future<AdvancedMessage> Function(
    {required int count, Message? startMsg});

/// Bounds the UI wait without treating a Dart timeout as native cancellation.
/// Each route retains at most two unfinished reads, including timed-out reads.
class ChatHistoryReadGate {
  ChatHistoryReadGate({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;
  final _pending =
      <(ChatHistoryReader, int, String?, int), Future<AdvancedMessage>>{};
  bool _closed = false;
  int _revision = 0;

  Future<AdvancedMessage> read(ChatHistoryReader reader,
      {required int count, required int revision, Message? startMsg}) async {
    final elapsed = Stopwatch()..start();
    final key = (reader, count, startMsg?.clientMsgID, revision);
    Duration remaining() {
      final value = timeout - elapsed.elapsed;
      if (value <= Duration.zero) {
        throw TimeoutException('History reads are still pending', timeout);
      }
      return value;
    }

    while (true) {
      if (_closed || revision != _revision) {
        throw StateError('History window changed while waiting for a read');
      }
      final budget = remaining();
      final existing = _pending[key];
      if (existing != null) return existing.timeout(budget);
      if (_pending.length < 2) {
        final started =
            Future.sync(() => reader(count: count, startMsg: startMsg))
                .then((result) {
          // OpenIM can resolve the Future with partial rows and an error code.
          // Reject the whole page before any loader mutates rows or cursors.
          // Older SDKs and local fixtures may omit the success code.
          if (result.errCode != null && result.errCode != 0) {
            throw PlatformException(
                code: result.errCode.toString(),
                message: result.errMsg ?? 'History query failed');
          }
          final cursor = result.scanCursor;
          if (result.scanLimited == true || cursor != null) {
            if (result.scanLimited != true ||
                result.isEnd == true ||
                cursor == null ||
                cursor.clientMsgID?.isNotEmpty != true ||
                cursor.conversationID.isEmpty ||
                (cursor.seq ?? 0) <= 0 ||
                (cursor.sendTime ?? 0) <= 0 ||
                !cursor.advancesFrom(startMsg)) {
              throw StateError('History scan returned an invalid continuation');
            }
          }
          return result;
        });
        _pending[key] = started;
        void release() {
          if (identical(_pending[key], started)) _pending.remove(key);
        }

        // Observe late errors even when every UI waiter has timed out. A retry
        // uses this native Future until it finishes, not another SDK query.
        unawaited(started.then<void>((_) => release(),
            onError: (Object _, StackTrace __) => release()));
        return started.timeout(budget);
      }
      // A date seek needs both directions while an earlier page may still be
      // finishing. Wait for capacity within the same deadline, then recheck
      // the window before issuing anything. Timeout never releases a slot.
      await Future.any(_pending.values.map((request) => request.then<void>(
          (_) {},
          onError: (Object _, StackTrace __) {}))).timeout(budget);
    }
  }

  void invalidate(int revision) => _revision = revision;

  void close() {
    _closed = true;
    _pending.clear();
  }
}
