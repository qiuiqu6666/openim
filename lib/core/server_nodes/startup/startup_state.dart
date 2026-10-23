import '../node_endpoint.dart';

enum StartupStage {
  initializing,
  probing,
  switching,
  ready,
  degraded,
  retrying,
  unavailable
}

/// Health belongs to one network generation, endpoint and observation time.
class StartupHealth {
  StartupHealth(this.endpoint, this.generation, Map<String, String> services,
      {DateTime? checkedAt})
      : services = Map.unmodifiable(services),
        checkedAt = checkedAt ?? DateTime.now();
  final NodeEndpoint endpoint;
  final int generation;
  final DateTime checkedAt;
  // ok, pending, or sanitized error category; never response bodies.
  final Map<String, String> services;
  bool get apiReady => services['chat'] == 'ok' && services['imApi'] == 'ok';
  bool get fullyHealthy => apiReady && services['imWs'] == 'ok';
}

class StartupState {
  const StartupState(this.stage,
      {this.generation = 0,
      this.attempt = 0,
      this.health,
      this.showDetails = false,
      this.showActions = false});
  final StartupStage stage;
  final int generation, attempt;
  final StartupHealth? health;
  final bool showDetails, showActions;
}
