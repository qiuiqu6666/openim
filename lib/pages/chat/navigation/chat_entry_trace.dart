import 'package:flutter/foundation.dart';

/// Monotonic entry timing; never records account IDs or message contents.
/// Frame milestones mean a Flutter paint submission, not display scan-out.
class ChatEntryTrace {
  ChatEntryTrace(this.sessionType, {int Function()? elapsedMicroseconds})
      : id = ++_next,
        _elapsedMicroseconds = elapsedMicroseconds {
    mark('tap');
  }
  static int _next = 0;
  final int id;
  final int? sessionType;
  final Stopwatch _watch = Stopwatch()..start();
  final int Function()? _elapsedMicroseconds;
  final _stages = <String, int>{};
  bool _closed = false;
  Map<String, double> get milliseconds => Map.unmodifiable(
      _stages.map((key, value) => MapEntry(key, value / 1000)));
  bool get listInteractive => _stages.containsKey('list_interactive');
  bool get transitionFinished => _stages.containsKey('transition_finished');
  bool get complete => listInteractive && transitionFinished;

  void mark(String stage) {
    if (_closed || _stages.containsKey(stage)) return;
    final elapsed = _elapsedMicroseconds?.call() ?? _watch.elapsedMicroseconds;
    _stages[stage] = elapsed;
    if (!kReleaseMode) {
      debugPrint('[ChatEntry] id=$id type=$sessionType stage=$stage '
          'elapsedMs=${elapsed / 1000}');
    }
  }

  void painted(
      {required bool publishable,
      required bool hasVisibleMessages,
      required bool contentVisible,
      required bool canInteract,
      required bool current}) {
    if (!current || !publishable || !contentVisible) return;
    mark(hasVisibleMessages
        ? 'first_correct_message_frame'
        : 'first_empty_frame');
    if (canInteract) mark('list_interactive');
  }

  void close() {
    _closed = true;
    _watch.stop();
  }
}
