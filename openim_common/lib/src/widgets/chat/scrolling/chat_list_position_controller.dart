import 'package:flutter/foundation.dart';

/// Positions a lazy chat list by message identity, without estimating heights.
/// Attach this to one ChatListView or ChatListViewport at a time.
class ChatListPositionController {
  Object? _owner;
  Future<bool> Function(String, double)? _jump;
  VoidCallback? _cancel;
  bool _disposed = false;

  /// Resolves after the message has painted in the current chat viewport.
  /// A missing message, cancellation, or detached viewport resolves to false.
  Future<bool> jumpToMessage(String messageID, {double alignment = 0.5}) {
    assert(alignment >= 0 && alignment <= 1);
    if (_disposed || messageID.isEmpty || !alignment.isFinite) {
      return Future.value(false);
    }
    return _jump?.call(messageID, alignment.clamp(0.0, 1.0)) ??
        Future.value(false);
  }

  /// Invalidates a pending position request before an explicit scroll or exit.
  void cancel() {
    if (!_disposed) _cancel?.call();
  }

  /// Used by the owning chat viewport to bind its positioning callbacks.
  void attach(Object owner, Future<bool> Function(String, double) jump,
      VoidCallback cancel) {
    if (_disposed) return;
    assert(_owner == null || identical(_owner, owner),
        'A chat position controller can only control one viewport.');
    if (!identical(_owner, owner)) _cancel?.call();
    _owner = owner;
    _jump = jump;
    _cancel = cancel;
  }

  /// Used by the owning chat viewport to release its positioning callbacks.
  void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _cancel?.call();
    _owner = null;
    _jump = null;
    _cancel = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancel?.call();
    _owner = null;
    _jump = null;
    _cancel = null;
  }
}
