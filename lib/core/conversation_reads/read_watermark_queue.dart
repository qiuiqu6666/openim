import 'dart:async';

import 'conversation_batch_read_api.dart';

/// Durable, account-scoped cutoffs. A retry never prepares a newer target.
class ReadWatermarkQueue {
  ReadWatermarkQueue({
    required Map<String, int> targets,
    required Map<String, int> confirmed,
    required this.save,
    required this.apply,
    required this.isCurrent,
    required this.changed,
    required this.acknowledged,
    required this.onError,
  })  : _targets = Map.of(targets),
        _confirmed = Map.of(confirmed);

  Map<String, int> _targets, _confirmed;
  final Future<void> Function(Map<String, int>, Map<String, int>) save;
  final Future<Set<String>> Function(List<BatchReadTarget>) apply;
  final bool Function() isCurrent;
  final void Function() changed;
  final void Function(List<String>) acknowledged;
  final void Function(Object) onError;
  Future<void> _writes = Future.value();
  bool _running = false, _closed = false, _foreground = true;
  Timer? _retry;
  int _failures = 0;

  int through(String id) => _targets[id] ?? 0;
  bool get _active => !_closed && isCurrent();
  bool get _canSend => _active && _foreground;

  Future<void> _serialize(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object e) {
      onError(e);
    });
    return next;
  }

  Future<void> enqueue(BatchReadTarget target) async {
    await _serialize(() async {
      if (!_active || target.hasReadSeq <= through(target.conversationID)) {
        return;
      }
      final next = {..._targets, target.conversationID: target.hasReadSeq};
      // Publish only after persistence succeeds. A crash before HTTP is safe.
      await save(next, _confirmed);
      if (!_active) return;
      _targets = next;
      changed();
    });
    kick();
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) {
      kick();
    } else {
      _retry?.cancel();
      _retry = null;
    }
  }

  void kick() {
    if (!_canSend || _running) return;
    _retry?.cancel();
    _retry = null;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (!_canSend || _running) return;
    _running = true;
    // A per-conversation rejection must not block unrelated later batches.
    // Retry rejected IDs on the existing backoff, at their frozen cutoffs.
    final rejected = <String>{};
    try {
      while (_canSend) {
        final batch = [
          for (final e in _targets.entries)
            if (!rejected.contains(e.key) && e.value > (_confirmed[e.key] ?? 0))
              BatchReadTarget(e.key, e.value)
        ].take(100).toList();
        if (batch.isEmpty) break;
        final success = await apply(batch);
        if (!_active) return;
        final done =
            batch.where((t) => success.contains(t.conversationID)).toList();
        if (done.isNotEmpty) {
          await _serialize(() async {
            if (!_active) return;
            final next = Map.of(_confirmed);
            for (final t in done) {
              if (t.hasReadSeq > (next[t.conversationID] ?? 0)) {
                next[t.conversationID] = t.hasReadSeq;
              }
            }
            await save(_targets, next);
            if (!_active) return;
            _confirmed = next;
            acknowledged(done.map((t) => t.conversationID).toList());
          });
        }
        if (done.length != batch.length) {
          rejected.addAll(batch
              .where((t) => !success.contains(t.conversationID))
              .map((t) => t.conversationID));
        }
      }
      if (rejected.isNotEmpty) {
        throw StateError('Read cutoff not acknowledged');
      }
      _failures = 0;
    } catch (e) {
      if (_active) {
        ++_failures;
        onError(e);
      }
    } finally {
      _running = false;
      if (_canSend &&
          _targets.entries.any((e) => e.value > (_confirmed[e.key] ?? 0))) {
        final seconds = (2 << _failures.clamp(0, 5)).clamp(2, 60);
        _retry = Timer(Duration(seconds: seconds), kick);
      }
    }
  }

  void close() {
    _closed = true;
    _retry?.cancel();
  }
}
