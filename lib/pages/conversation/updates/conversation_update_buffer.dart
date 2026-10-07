import 'dart:async';

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// SDK metadata can be coalesced; persisted message events remain untouched.
class ConversationUpdateBuffer {
  ConversationUpdateBuffer({required this.publish, required this.delay});
  final void Function(List<ConversationInfo>) publish;
  final Duration Function() delay;
  final _pending = <String, ConversationInfo>{};
  Timer? _timer;
  bool _closed = false;

  void add(List<ConversationInfo> changes) {
    if (_closed) return;
    for (final info in changes) {
      _pending[info.conversationID] = info;
    }
    if (_pending.isNotEmpty) _timer ??= Timer(delay(), flush);
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
    clear();
  }
}
