import 'dart:async';
import 'dart:collection';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'message_notification_target.dart';

/// Notification presentation is best-effort. Message delivery is never queued
/// here. Share in-flight metadata reads and bound native work across sources.
class NotificationLookupPool {
  NotificationLookupPool(this.fetch,
      {this.concurrency = 4, this.maxQueued = 128});
  final Future<ConversationInfo> Function(MessageNotificationTarget) fetch;
  final int concurrency, maxQueued;
  final _jobs = <String, _Lookup>{};
  final _queue = Queue<_Lookup>();
  int _active = 0;

  Future<ConversationInfo?> read(MessageNotificationTarget target) {
    final key = '${target.sessionKey}|${target.sessionType}|${target.sourceID}';
    final existing = _jobs[key];
    if (existing != null) return existing.result.future;
    if (_queue.length >= maxQueued) _finish(_queue.removeFirst(), null);
    final job = _Lookup(key, target);
    _jobs[key] = job;
    _queue.add(job);
    _drain();
    return job.result.future;
  }

  void _drain() {
    while (_active < concurrency && _queue.isNotEmpty) {
      final job = _queue.removeFirst();
      _active++;
      unawaited(_run(job));
    }
  }

  Future<void> _run(_Lookup job) async {
    try {
      _finish(job, await fetch(job.target));
    } catch (_) {
      _finish(job, null);
    } finally {
      _active--;
      _drain();
    }
  }

  void _finish(_Lookup job, ConversationInfo? value) {
    if (identical(_jobs[job.key], job)) _jobs.remove(job.key);
    if (!job.result.isCompleted) job.result.complete(value);
  }

  void clear() {
    for (final job in _jobs.values.toList()) {
      _finish(job, null);
    }
    _queue.clear();
  }
}

class _Lookup {
  _Lookup(this.key, this.target);
  final String key;
  final MessageNotificationTarget target;
  final result = Completer<ConversationInfo?>();
}
