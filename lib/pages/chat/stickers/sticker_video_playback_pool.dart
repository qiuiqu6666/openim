import 'dart:async';
import 'dart:collection';

/// Includes initializing and disposing players in the decoder budget.
class StickerVideoPlaybackPool {
  static final shared = StickerVideoPlaybackPool();
  final _waiting = LinkedHashMap<Object, Completer<StickerVideoLease?>>();
  int _active = 0;
  static const limit = 2;

  Future<StickerVideoLease?> acquire(Object owner) {
    final pending = _waiting[owner];
    if (pending != null) return pending.future;
    final request = Completer<StickerVideoLease?>();
    _waiting[owner] = request;
    _drain();
    return request.future;
  }

  void cancel(Object owner) => _waiting.remove(owner)?.complete(null);

  void _drain() {
    while (_active < limit && _waiting.isNotEmpty) {
      final owner = _waiting.keys.first;
      final request = _waiting.remove(owner)!;
      _active++;
      request.complete(StickerVideoLease._(() {
        _active--;
        _drain();
      }));
    }
  }
}

class StickerVideoLease {
  StickerVideoLease._(this._release);
  void Function()? _release;

  void release() {
    final callback = _release;
    _release = null;
    callback?.call();
  }
}
