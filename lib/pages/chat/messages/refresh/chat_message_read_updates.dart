import 'package:flutter/foundation.dart';

/// Only mounted rows subscribe. Read changes do not invalidate timeline order,
/// time markers, history snapshots, or the viewport's message index.
class ChatMessageReadUpdates {
  final _listeners = <String, Set<VoidCallback>>{};
  bool _closed = false;

  Listenable forMessage(String? id) => _MessageReadListenable(this, id);

  void notify(Set<String> ids) {
    if (_closed) return;
    for (final id in ids) {
      for (final listener in List<VoidCallback>.of(_listeners[id] ?? {})) {
        listener();
      }
    }
  }

  void close() {
    _closed = true;
    _listeners.clear();
  }
}

class _MessageReadListenable implements Listenable {
  const _MessageReadListenable(this.owner, this.id);
  final ChatMessageReadUpdates owner;
  final String? id;

  @override
  void addListener(VoidCallback listener) {
    if (!owner._closed && id?.isNotEmpty == true) {
      (owner._listeners[id!] ??= {}).add(listener);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    final listeners = owner._listeners[id];
    listeners?.remove(listener);
    if (listeners?.isEmpty == true) owner._listeners.remove(id);
  }

  @override
  bool operator ==(Object other) =>
      other is _MessageReadListenable &&
      identical(owner, other.owner) &&
      id == other.id;

  @override
  int get hashCode => Object.hash(owner, id);
}
