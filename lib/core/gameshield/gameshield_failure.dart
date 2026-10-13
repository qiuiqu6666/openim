enum GameShieldFailureKind {
  configuration,
  unsupportedPlatform,
  unavailableSdk,
  startFailed,
  invalidEndpoints
}

/// Never retain a native error or a token in the user-visible failure object.
class GameShieldFailure implements Exception {
  const GameShieldFailure(this.kind);
  final GameShieldFailureKind kind;
  @override
  String toString() => 'GameShieldFailure(${kind.name})';
}
