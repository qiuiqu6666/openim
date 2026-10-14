import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

import '../../network/transport_state.dart';

/// Wakes the existing native SDK reconnect loop without replacing its session.
/// A successful wake-up is not evidence that the socket has connected.
class IMConnectionRecovery with WidgetsBindingObserver {
  IMConnectionRecovery({
    required this.isCurrent,
    required this.isDisconnected,
    this.isSyncFailed,
    required this.wake,
    required this.onError,
    Stream<List<ConnectivityResult>>? networkChanges,
    Future<List<ConnectivityResult>> Function()? networkSnapshot,
    this.syncRecoverySignals,
    this.onWakeSucceeded,
    this.retryInterval = const Duration(seconds: 3),
    this.connectedCheckInterval = const Duration(minutes: 1),
    this.wakeTimeout = const Duration(seconds: 18),
  })  : _networkChanges = networkChanges,
        _networkSnapshot = networkSnapshot ??
            (networkChanges == null ? Connectivity().checkConnectivity : null);

  final bool Function() isCurrent;
  final bool Function() isDisconnected;
  final bool Function()? isSyncFailed;
  final Future<void> Function(bool Function() isCurrentAttempt) wake;
  final void Function(Object) onError;
  final Duration retryInterval;
  final Duration connectedCheckInterval;
  final Duration wakeTimeout;
  final Stream<List<ConnectivityResult>>? _networkChanges;
  final Future<List<ConnectivityResult>> Function()? _networkSnapshot;
  final Stream<void>? syncRecoverySignals;
  final VoidCallback? onWakeSucceeded;
  StreamSubscription<List<ConnectivityResult>>? _network;
  StreamSubscription<void>? _syncRecovery;
  Timer? _retry;
  int _scheduleRevision = 0;
  bool _active = false;
  bool _foreground = true;
  Completer<void>? _wakeWait;
  bool _wakeFailed = false;
  bool _verificationPending = false;
  final _transport = NetworkTransportState();

  void start() {
    if (_active) return;
    _active = true;
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _network = (_networkChanges ?? Connectivity().onConnectivityChanged).listen(
      (results) {
        if (!_transport.update(results)) return;
        _transportChanged();
      },
      onError: (Object error) {
        if (_active && isCurrent()) onError(error);
      },
    );
    _syncRecovery = syncRecoverySignals?.listen((_) {
      // Connection transitions and sync failures may arrive without an OS
      // event. Sync finishes are not fed back here: our own wake must not
      // create a repeating successful-sync/wake loop.
      if (!_verificationPending && _wakeWait == null) {
        _schedule(verifyConnection: true);
      }
    });
    _schedule();
    unawaited(_refreshTransport());
  }

  void _transportChanged() {
    if (!_transport.online) {
      _cancelWakeWait();
      _schedule();
    } else {
      unawaited(recoverNow());
    }
  }

  Future<void> _refreshTransport() async {
    final read = _networkSnapshot;
    if (read == null || !_active || !_foreground || !isCurrent()) return;
    final changed = await _transport.refresh(read);
    if (changed && _active && _foreground && isCurrent()) _transportChanged();
  }

  void _schedule({bool verifyConnection = false}) {
    _retry?.cancel();
    _verificationPending = false;
    final revision = ++_scheduleRevision;
    if (!_active || !_foreground || !_transport.online || !isCurrent()) return;
    // The native SDK owns heartbeat/reconnect. Healthy foreground polls only
    // recheck failure state; they do not start another full metadata sync.
    final checkConnected =
        !isDisconnected() && isSyncFailed?.call() != true && !_wakeFailed;
    final delay = verifyConnection || !checkConnected
        ? retryInterval
        : connectedCheckInterval;
    _verificationPending = verifyConnection;
    _retry = Timer(delay, () async {
      _verificationPending = false;
      if (verifyConnection ||
          isDisconnected() ||
          isSyncFailed?.call() == true ||
          _wakeFailed) {
        await _wake();
      }
      if (revision == _scheduleRevision) _schedule();
    });
  }

  /// Explicit catch-up after replacing a route, sharing retry and cancellation
  /// ownership with foreground/network recovery.
  Future<void> recoverNow() async {
    await _wake();
    _schedule();
  }

  Future<void> _wake() async {
    if (!_active ||
        !_foreground ||
        !_transport.online ||
        _wakeWait != null ||
        !isCurrent()) {
      return;
    }
    final cancelled = Completer<void>();
    _wakeWait = cancelled;
    bool currentAttempt() =>
        _active &&
        _foreground &&
        _transport.online &&
        identical(_wakeWait, cancelled) &&
        isCurrent();
    try {
      // A native callback may never return after suspension. These idempotent
      // wake signals may be retried; this timeout is not native cancellation.
      await Future.any([wake(currentAttempt), cancelled.future])
          .timeout(wakeTimeout);
      if (currentAttempt()) {
        _wakeFailed = false;
        onWakeSucceeded?.call();
      }
    } catch (error) {
      if (currentAttempt()) {
        _wakeFailed = true;
        onError(error);
      }
    } finally {
      if (identical(_wakeWait, cancelled)) _wakeWait = null;
    }
  }

  void _cancelWakeWait() {
    _wakeWait?.complete();
    _wakeWait = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    if (_foreground) {
      unawaited(_refreshTransport());
      // The server acknowledgement checks the existing socket and requests
      // incremental sync. A successful acknowledgement needs no second wake.
      unawaited(recoverNow());
    } else {
      _transport.invalidateSnapshot();
      _cancelWakeWait();
      _schedule();
    }
  }

  void close() {
    _active = false;
    _transport.invalidateSnapshot();
    _cancelWakeWait();
    _retry?.cancel();
    ++_scheduleRevision;
    _retry = null;
    unawaited(_network?.cancel());
    _network = null;
    unawaited(_syncRecovery?.cancel());
    _syncRecovery = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
