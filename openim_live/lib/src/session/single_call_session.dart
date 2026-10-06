import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/call_types.dart';

/// A cancellable lease for one asynchronous connection attempt.
class CallAttempt {
  CallAttempt._(this._session, this._generation);
  final SingleCallSession _session;
  final int _generation;
  bool get isCurrent => _session.active && _session._generation == _generation;
}

class CallTermination {
  const CallTermination(this.state, this.duration, this.notifyPeer,
      {this.error, this.stackTrace});
  final CallState state;
  final int duration;
  final bool notifyPeer;
  final Object? error;
  final StackTrace? stackTrace;
}

/// Owns deadlines, connection admission and a single terminal transaction.
/// Media remains owned by the room adapter; UI disposal cannot revive a lease.
class SingleCallSession extends ChangeNotifier {
  SingleCallSession({
    required CallState initialState,
    required this.connect,
    required this.release,
    required this.onTerminated,
    required this.onClosed,
    this.ringingTimeout = const Duration(seconds: 30),
    this.connectionTimeout = const Duration(seconds: 20),
    DateTime Function()? now,
  })  : state = initialState,
        _now = now ?? DateTime.now;

  final Future<void> Function(CallAttempt attempt, bool outgoing) connect;
  final Future<void> Function() release;
  final Future<void> Function(CallTermination result) onTerminated;
  final VoidCallback onClosed;
  final Duration ringingTimeout, connectionTimeout;
  final DateTime Function() _now;
  CallState state;
  bool active = true;
  bool _connecting = false, _transportReady = false, _peerPresent = false;
  bool _disposed = false;
  int _generation = 0;
  DateTime? _connectedAt;
  Timer? _deadline, _ticker, _reconnectDeadline;
  Future<void>? _ending;
  Object? cleanupError;

  bool get connected => _connectedAt != null;
  int get duration => _connectedAt == null
      ? 0
      : _now().difference(_connectedAt!).inSeconds.clamp(0, 86400);

  void armDeadline() {
    if (!active || connected || _deadline != null) return;
    _deadline = Timer(ringingTimeout, () => unawaited(end(CallState.timeout)));
  }

  Future<void> dial() => _begin(outgoing: true);

  Future<void> accept() {
    if (state != CallState.beCalled) return Future.value();
    return _begin(outgoing: false);
  }

  Future<void> _begin({required bool outgoing}) async {
    if (!active || _connecting || _transportReady || connected) return;
    _connecting = true;
    state = CallState.connecting;
    _changed();
    final attempt = CallAttempt._(this, ++_generation);
    try {
      await connect(attempt, outgoing).timeout(connectionTimeout);
      if (!attempt.isCurrent) return;
      _transportReady = true;
      _connecting = false;
      if (_peerPresent) {
        peerConnected();
      } else if (outgoing) {
        state = CallState.call;
        _changed();
      }
    } catch (error, stack) {
      if (attempt.isCurrent) {
        await end(CallState.networkError, error: error, stackTrace: stack);
      }
    }
  }

  void peerAccepted() {
    if (!active || connected) return;
    state = CallState.connecting;
    _changed();
  }

  void peerConnected() {
    if (!active) return;
    _peerPresent = true;
    if (!_transportReady) return;
    _deadline?.cancel();
    _reconnectDeadline?.cancel();
    _connectedAt ??= _now();
    state = CallState.calling;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    _changed();
  }

  void reconnecting() {
    if (!active || !connected) return;
    state = CallState.connecting;
    _reconnectDeadline?.cancel();
    _reconnectDeadline = Timer(
        connectionTimeout,
        () => unawaited(end(CallState.networkError,
            error: TimeoutException('Call reconnection timed out'))));
    _changed();
  }

  Future<void> end(CallState outcome,
      {bool notifyPeer = true, Object? error, StackTrace? stackTrace}) {
    if (_ending != null) return _ending!;
    // Invalidating the lease precedes every await and external callback.
    final result = CallTermination(outcome, duration, notifyPeer,
        error: error, stackTrace: stackTrace);
    active = false;
    ++_generation;
    _deadline?.cancel();
    _ticker?.cancel();
    _reconnectDeadline?.cancel();
    state = outcome;
    final completion = Completer<void>();
    _ending = completion.future;
    _changed();
    unawaited(() async {
      try {
        // Send the terminal signal immediately; slow native release must not
        // leave the peer ringing. Admission stays closed until both finish.
        await Future.wait([
          Future.sync(release).catchError((Object e) {
            cleanupError ??= e;
          }),
          Future.sync(() => onTerminated(result)).catchError((Object e) {
            cleanupError ??= e;
          }),
        ]);
      } finally {
        try {
          onClosed();
        } catch (e) {
          cleanupError ??= e;
        } finally {
          completion.complete();
        }
      }
    }());
    return completion.future;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (active) unawaited(end(CallState.cancel, notifyPeer: false));
    super.dispose();
  }
}
