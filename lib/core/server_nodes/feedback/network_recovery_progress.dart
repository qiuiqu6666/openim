import 'package:flutter/foundation.dart';

enum NetworkRecoveryStage { checking, startingShield, retrying }

/// A route operation owns its feedback until it completes or is replaced.
class NetworkRecoveryProgress extends ValueNotifier<NetworkRecoveryStage?> {
  NetworkRecoveryProgress() : super(null);

  static final instance = NetworkRecoveryProgress();
  Object? _owner;

  NetworkRecoveryOperation begin(NetworkRecoveryStage stage) {
    final owner = _owner = Object();
    value = stage;
    return NetworkRecoveryOperation._(this, owner);
  }
}

class NetworkRecoveryOperation {
  NetworkRecoveryOperation._(this._progress, this._owner);
  final NetworkRecoveryProgress _progress;
  final Object _owner;

  void update(NetworkRecoveryStage stage) {
    if (identical(_progress._owner, _owner)) _progress.value = stage;
  }

  void close() {
    if (!identical(_progress._owner, _owner)) return;
    _progress._owner = null;
    _progress.value = null;
  }
}
