import 'package:flutter/foundation.dart';

enum NetworkRecoveryStage { checking, startingShield, retrying }

enum NetworkRecoveryContext { startup, reconnect }

@immutable
class NetworkRecoveryState {
  const NetworkRecoveryState(this.stage, this.context);
  final NetworkRecoveryStage stage;
  final NetworkRecoveryContext context;
}

/// A route operation owns its feedback until it completes or is replaced.
/// Runtime recovery is silent by default; only initial preparation may use HUD.
class NetworkRecoveryProgress extends ValueNotifier<NetworkRecoveryState?> {
  NetworkRecoveryProgress() : super(null);

  static final instance = NetworkRecoveryProgress();
  Object? _owner;

  NetworkRecoveryOperation begin(NetworkRecoveryStage stage,
      {NetworkRecoveryContext context = NetworkRecoveryContext.reconnect}) {
    final owner = _owner = Object();
    value = NetworkRecoveryState(stage, context);
    return NetworkRecoveryOperation._(this, owner);
  }
}

class NetworkRecoveryOperation {
  NetworkRecoveryOperation._(this._progress, this._owner);
  final NetworkRecoveryProgress _progress;
  final Object _owner;

  void update(NetworkRecoveryStage stage) {
    final current = _progress.value;
    if (identical(_progress._owner, _owner) &&
        current != null &&
        current.stage != stage) {
      _progress.value = NetworkRecoveryState(stage, current.context);
    }
  }

  void close() {
    if (!identical(_progress._owner, _owner)) return;
    _progress._owner = null;
    _progress.value = null;
  }
}
