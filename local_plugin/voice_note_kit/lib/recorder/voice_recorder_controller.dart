import 'package:flutter/foundation.dart';

/// Read-only state of the recorder attached to [VoiceRecorderController].
@immutable
class VoiceRecorderSnapshot {
  const VoiceRecorderSnapshot({
    this.isStarting = false,
    this.isRecording = false,
    this.isStopping = false,
    this.seconds = 0,
    this.amplitude = 0,
  });

  final bool isStarting;
  final bool isRecording;
  final bool isStopping;
  final int seconds;

  /// Current native input level, normalized from -60..0 dB to 0..1.
  final double amplitude;
}

/// Controls the same recorder used by VoiceRecorderWidget's default UI.
///
/// A controller can be attached to only one mounted recorder at a time. The
/// widget owns native resources; disposing this controller does not transfer
/// their ownership or start another native recorder.
class VoiceRecorderController extends ChangeNotifier {
  VoiceRecorderSnapshot _snapshot = const VoiceRecorderSnapshot();
  Object? _owner;
  Future<void> Function()? _start;
  Future<void> Function()? _stop;
  Future<void> Function()? _cancel;
  bool _disposed = false;

  VoiceRecorderSnapshot get snapshot => _snapshot;

  Future<void> start() async {
    if (_disposed) return;
    await _start?.call();
  }

  Future<void> stop() async {
    if (_disposed) return;
    await _stop?.call();
  }

  Future<void> cancel() async {
    if (_disposed) return;
    await _cancel?.call();
  }

  /// Internal widget binding. Reattaching the same owner is harmless; sharing
  /// a controller between two live native recorders is rejected explicitly.
  void attach({
    required Object owner,
    required Future<void> Function() start,
    required Future<void> Function() stop,
    required Future<void> Function() cancel,
  }) {
    if (_disposed) {
      throw StateError('Cannot attach a disposed VoiceRecorderController');
    }
    if (_owner != null && !identical(_owner, owner)) {
      throw StateError('VoiceRecorderController already has a recorder');
    }
    _owner = owner;
    _start = start;
    _stop = stop;
    _cancel = cancel;
  }

  /// Detach before the widget begins asynchronous native cleanup. No listener
  /// is notified during widget disposal or controller replacement.
  void detach(Object owner) {
    if (_disposed || !identical(_owner, owner)) return;
    _owner = null;
    _start = null;
    _stop = null;
    _cancel = null;
    _snapshot = const VoiceRecorderSnapshot();
  }

  /// Internal state publication, ignored after detach or disposal.
  void updateSnapshot(Object owner, VoiceRecorderSnapshot value) {
    if (_disposed || !identical(_owner, owner)) return;
    final old = _snapshot;
    if (old.isStarting == value.isStarting &&
        old.isRecording == value.isRecording &&
        old.isStopping == value.isStopping &&
        old.seconds == value.seconds &&
        old.amplitude == value.amplitude) {
      return;
    }
    _snapshot = value;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _owner = null;
    _start = null;
    _stop = null;
    _cancel = null;
    _snapshot = const VoiceRecorderSnapshot();
    super.dispose();
  }
}
