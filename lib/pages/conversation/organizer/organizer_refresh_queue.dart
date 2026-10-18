import 'dart:async';

/// Serializes refreshes and preserves a queued user's feedback ownership.
class OrganizerRefreshQueue {
  OrganizerRefreshQueue({required this.isCurrent, required this.run});

  final bool Function() isCurrent;
  final Future<void> Function(bool userInitiated, String source) run;
  Future<void>? _active;
  ({bool userInitiated, String source})? _pending;

  Future<void> request({required bool userInitiated, required String source}) {
    if (!isCurrent()) return Future.value();
    final intent = (userInitiated: userInitiated, source: source);
    if (_active != null) {
      // Automatic callbacks must not downgrade an already queued manual retry.
      if (_pending?.userInitiated != true) _pending = intent;
      return _active!;
    }
    final done = Completer<void>();
    _active = done.future;
    unawaited(() async {
      try {
        var next = intent;
        while (isCurrent()) {
          await run(next.userInitiated, next.source);
          final pending = _pending;
          _pending = null;
          if (pending == null) break;
          next = pending;
        }
        done.complete();
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _pending = null;
        _active = null;
      }
    }());
    return done.future;
  }
}
