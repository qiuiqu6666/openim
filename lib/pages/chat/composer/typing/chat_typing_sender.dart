import 'dart:async';
import '../../../../core/privacy/typing_visibility_preferences.dart';

/// Serializes input notices and rechecks privacy at the transport boundary.
class ChatTypingSender {
  ChatTypingSender(
      {required this.owner, required this.isCurrent, required this.send}) {
    _subscription = TypingVisibilityPreferences.changes.listen((changed) {
      if (changed == owner && !TypingVisibilityPreferences.read(owner)) {
        report(false);
      }
    });
  }

  final String owner;
  final bool Function() isCurrent;
  final Future<void> Function(bool) send;
  late final StreamSubscription<String> _subscription;
  Future<void> _pending = Future.value();
  bool _closed = false;
  bool _announced = false;
  Future<void> get settled => _pending;

  void report(bool typing) {
    if (_closed || !isCurrent()) return;
    _pending = _pending.then((_) async {
      if (_closed || !isCurrent()) return;
      if (typing && !TypingVisibilityPreferences.read(owner)) return;
      if (!typing && !_announced) return;
      // A failed request can still have reached the server. Keep the stop
      // obligation until a later stop succeeds, without retrying automatically.
      if (typing) _announced = true;
      await send(typing);
      if (!typing) _announced = false;
    }).catchError((Object _) {
      /* Transient typing must not disrupt editing. */
    });
  }

  void dispose() {
    _closed = true;
    unawaited(_subscription.cancel());
  }
}
