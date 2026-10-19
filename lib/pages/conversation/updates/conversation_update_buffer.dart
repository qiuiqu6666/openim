import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// SDK metadata can be coalesced; persisted message events remain untouched.
class ConversationUpdateBuffer {
  ConversationUpdateBuffer({required this.publish, required this.delay});
  final void Function(List<ConversationInfo>) publish;
  final Duration Function() delay;
  final _visibleViews = <Object>{};
  bool _visibilityKnown = false;
  bool _foreground = true;
  bool get _visible =>
      _foreground && (!_visibilityKnown || _visibleViews.isNotEmpty);
  static const hiddenDelay = Duration(seconds: 1);
  final _pending = <String, ConversationInfo>{};
  Timer? _timer;
  bool _closed = false;

  void add(List<ConversationInfo> changes) {
    if (_closed) return;
    for (final info in changes) {
      _pending[info.conversationID] = info;
    }
    if (_pending.isNotEmpty) {
      _timer ??= Timer(_visible ? delay() : hiddenDelay, flush);
    }
  }

  /// Multiple tabs and archive pages share one buffer. A hidden tab must not
  /// override another visible consumer. Explicit flushes remain immediate for
  /// read reconciliation, snapshots and user mutations.
  void setViewActive(Object owner, bool active) {
    if (_closed) return;
    final wasVisible = _visible;
    _visibilityKnown = true;
    active ? _visibleViews.add(owner) : _visibleViews.remove(owner);
    _visibilityChanged(wasVisible);
  }

  void removeView(Object owner) => setViewActive(owner, false);

  void setForeground(bool foreground) {
    final wasVisible = _visible;
    _foreground = foreground;
    _visibilityChanged(wasVisible);
  }

  void _visibilityChanged(bool wasVisible) {
    if (_closed || wasVisible == _visible) return;
    _timer?.cancel();
    _timer = null;
    if (_pending.isNotEmpty) {
      // Returning views may notify during build. Publish on the next event
      // turn, never synchronously invalidate another widget during its build.
      _timer = Timer(_visible ? Duration.zero : hiddenDelay, flush);
    }
  }

  void remove(String id) => _pending.remove(id);

  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_closed || _pending.isEmpty) return;
    final changes = _pending.values.toList(growable: false);
    _pending.clear();
    publish(changes);
  }

  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }

  void close() {
    _closed = true;
    _visibleViews.clear();
    clear();
  }
}
