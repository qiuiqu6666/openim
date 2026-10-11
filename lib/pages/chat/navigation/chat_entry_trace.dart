import 'package:flutter/foundation.dart';

/// Debug-only timing; never records account IDs, tokens or message contents.
class ChatEntryTrace {
  ChatEntryTrace(this.sessionType) : id = ++_next {
    mark('tap');
  }
  static int _next = 0;
  final int id;
  final int? sessionType;
  final Stopwatch _watch = Stopwatch()..start();
  void mark(String stage) {
    if (kDebugMode) {
      debugPrint('[ChatEntry] id=$id type=$sessionType stage=$stage '
          'elapsedMs=${_watch.elapsedMilliseconds}');
    }
  }
}
