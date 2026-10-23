import 'dart:async';
import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../network/transport_state.dart';
import '../../youmeng/youmeng_runtime.dart';
import '../node_endpoint.dart';
import 'startup_route_probe.dart';
import 'startup_state.dart';
import 'startup_trace.dart';

typedef StartupProbe = Future<void> Function(
    NodeEndpoint, int, void Function(StartupHealth));

/// One route commit before SDK initialization. Runtime IM recovery owns all
/// later changes; a late startup callback can never reinitialize the SDK.
class StartupNetworkPreparation extends GetxService
    with WidgetsBindingObserver {
  StartupNetworkPreparation(
      {StartupProbe? probe,
      this.cancelProbe,
      Future<void> Function()? prepareShield,
      Future<void> Function()? cancelShield,
      this.shieldEnabled = YoumengRuntime.enabled,
      this.networkChanges,
      this.networkSnapshot,
      NodeEndpoint Function()? readCurrent,
      void Function(NodeEndpoint)? install,
      StartupTrace? trace,
      double Function()? jitter})
      : _probeOverride = probe,
        _prepareShield = prepareShield ?? YoumengRuntime.ensureNativeReady,
        _cancelShield = cancelShield ?? YoumengRuntime.cancelNativePreparation,
        _readCurrent = readCurrent ?? NodeEndpoint.current,
        _install = install ?? _installRoute,
        trace = trace ?? StartupTrace(),
        _jitter = jitter ?? Random().nextDouble;
  final StartupProbe? _probeOverride;
  final void Function()? cancelProbe;
  final Future<void> Function() _prepareShield, _cancelShield;
  final bool shieldEnabled;
  final Stream<List<ConnectivityResult>>? networkChanges;
  final Future<List<ConnectivityResult>> Function()? networkSnapshot;
  final NodeEndpoint Function() _readCurrent;
  final void Function(NodeEndpoint) _install;
  final double Function() _jitter;
  final StartupTrace trace;
  final state = ValueNotifier(const StartupState(StartupStage.initializing));
  final _probe = StartupRouteProbe();
  final _transport = NetworkTransportState();
  final _completion = Completer<void>();
  StreamSubscription<List<ConnectivityResult>>? _network;
  Timer? _retry, _details, _actions;
  bool _started = false, _closed = false, _foreground = true;
  bool ready = false, handoffComplete = false;
  bool sdkRecoveryVisible = false, _sdkRetrying = false;
  bool loginRecoveryVisible = false;
  Future<void> Function()? _retryLogin;
  bool _loginRetrying = false;
  int _loginFailures = 0;
  Future<void> Function()? _retrySdk;
  bool _showDetails = false, _showActions = false;
  int _generation = 0, _attempt = 0, _failures = 0;
  int? _shieldGeneration;

  static void _installRoute(NodeEndpoint node) {
    Config.useRuntimeNetworkRoute(RuntimeNetworkRoute(
        authUrl: node.chatApi,
        apiUrl: node.imApi,
        wsUrl: node.imWs,
        customerServiceUrl:
            node.customerServiceUrl ?? Config.customerServiceOriginUrl));
    dio.options.baseUrl = node.imApi;
  }

  Future<void> prepare() {
    if (_started || _closed) return _completion.future;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    unawaited(trace.metadata());
    _details = Timer(const Duration(seconds: 3), () {
      _showDetails = true;
      _publish(state.value.stage);
    });
    _actions = Timer(const Duration(seconds: 10), () {
      _showActions = true;
      _publish(state.value.stage);
    });
    _network = (networkChanges ?? Connectivity().onConnectivityChanged).listen(
        (values) {
      if (_transport.update(values)) {
        trace.event('network', {'types': values.map((e) => e.name).join(',')});
        _environmentChanged();
      }
    },
        onError: (Object error) => trace
            .event('network_error', {'type': error.runtimeType.toString()}));
    unawaited(_refreshNetwork());
    _round();
    return _completion.future;
  }

  Future<void> _refreshNetwork() async {
    if (await _transport.refresh(() async {
      final values =
          await (networkSnapshot ?? Connectivity().checkConnectivity)();
      trace.event(
          'network_snapshot', {'types': values.map((e) => e.name).join(',')});
      return values;
    })) {
      _environmentChanged();
    }
  }

  void _publish(StartupStage stage, [StartupHealth? health]) {
    if (_closed ||
        (ready &&
            stage != StartupStage.ready &&
            stage != StartupStage.degraded)) {
      return;
    }
    trace.event('state', {
      'from': state.value.stage.name,
      'to': stage.name,
      'generation': _generation,
      'attempt': _attempt
    });
    state.value = StartupState(stage,
        generation: _generation,
        attempt: _attempt,
        health: health ?? state.value.health,
        showDetails: _showDetails,
        showActions: _showActions);
  }

  bool _active(int generation) =>
      !_closed &&
      !ready &&
      _foreground &&
      _transport.online &&
      generation == _generation;

  void _invalidate() {
    _generation++;
    _retry?.cancel();
    _probe.cancel();
    cancelProbe?.call();
  }

  void retry() {
    if (ready && !_closed && _retrySdk != null && !_sdkRetrying) {
      final action = _retrySdk!;
      _retrySdk = null;
      _sdkRetrying = true;
      state.value = StartupState(StartupStage.initializing,
          generation: _generation,
          health: state.value.health,
          showDetails: true);
      unawaited(action().catchError((Object _) {
        sdkFailed(action);
      }).whenComplete(() => _sdkRetrying = false));
      return;
    }
    if (!_started || _closed || ready) return;
    _failures = 0;
    _invalidate();
    _round();
  }

  void _environmentChanged() {
    if (ready && !handoffComplete && !_closed) {
      if (_foreground && _transport.online) _resumeLogin();
      return;
    }
    if (_closed || ready) return;
    _invalidate();
    _failures = 0;
    unawaited(_cancelShield());
    _round();
  }

  void _round() {
    if (_closed || ready || !_started) return;
    if (!_foreground || !_transport.online) {
      _publish(StartupStage.unavailable);
      return;
    }
    final generation = _generation;
    final attempt = ++_attempt;
    _publish(_failures >= 3 ? StartupStage.unavailable : StartupStage.probing);
    final nodes = NodeEndpoint.candidates(_readCurrent());
    final builtIn = NodeEndpoint.isProduction(_readCurrent());
    final shield = shieldEnabled && builtIn;
    void scheduleRetry() {
      if (!_active(generation) || attempt != _attempt) return;
      _failures++;
      _publish(
          _failures >= 3 ? StartupStage.unavailable : StartupStage.retrying);
      final baseMs = _failures <= 2
          ? 500 * _failures
          : min(30000, 2000 * pow(2, min(_failures - 3, 4)).toInt());
      final delay =
          Duration(milliseconds: (baseMs * (0.8 + 0.2 * _jitter())).round());
      trace.event(
          'retry', {'delayMs': delay.inMilliseconds, 'failures': _failures});
      _retry?.cancel();
      _retry = Timer(delay, _round);
    }

    if (nodes.isNotEmpty) {
      unawaited(Future.wait(
              nodes.map((node) => _check(node, generation, attempt: attempt)))
          .then((_) => scheduleRetry()));
    }
    // Direct retries do not wait for native initialization or restart it.
    if (shield && _shieldGeneration != generation) {
      _shieldGeneration = generation;
      unawaited(() async {
        final clock = Stopwatch()..start();
        try {
          trace.event('shield_start', {'generation': generation});
          await _prepareShield().timeout(const Duration(seconds: 24));
          trace.event('shield_end', {
            'generation': generation,
            'durationMs': clock.elapsedMilliseconds
          });
          if (!_closed && generation == _generation) {
            await _check(NodeEndpoint.shield, generation);
          }
        } catch (error) {
          trace.event('shield_error', {
            'generation': generation,
            'durationMs': clock.elapsedMilliseconds,
            'type': error.runtimeType.toString()
          });
          if (!_closed && generation == _generation) {
            await _cancelShield();
            if (_active(generation)) {
              // Fresh samples after native failure, never cached pre-start results.
              await Future.wait(
                  nodes.map((n) => _check(n, generation, attempt: _attempt)));
            }
          }
        } finally {
          if (_shieldGeneration == generation) _shieldGeneration = null;
          if (nodes.isEmpty) scheduleRetry();
        }
      }());
    } else if (nodes.isEmpty) {
      scheduleRetry();
    }
  }

  Future<void> _check(NodeEndpoint node, int generation, {int? attempt}) async {
    final clock = Stopwatch()..start();
    trace.event('probe_start',
        {'route': node.diagnosticCode ?? 'custom', 'generation': generation});
    try {
      void accept(StartupHealth health) {
        trace.event('probe_health', {
          'route': node.diagnosticCode ?? 'custom',
          'generation': generation,
          'services': health.services
        });
        if (!_active(generation) ||
            (attempt != null && attempt != _attempt) ||
            health.generation != generation ||
            health.endpoint.signature != node.signature ||
            DateTime.now().difference(health.checkedAt).abs() >
                const Duration(seconds: 5) ||
            !health.apiReady) {
          return;
        }
        _publish(StartupStage.switching, health);
        if (!_active(generation)) return;
        _install(node);
        ready = true;
        _retry?.cancel();
        _details?.cancel();
        _actions?.cancel();
        _publish(
            health.fullyHealthy ? StartupStage.ready : StartupStage.degraded,
            health);
        trace.event('route_selected', {
          'route': node.diagnosticCode ?? 'custom',
          'reason': health.fullyHealthy
              ? 'all_services_verified'
              : 'apis_verified_im_pending'
        });
        _completion.complete();
      }

      if (_probeOverride != null) {
        await _probeOverride(node, generation, accept);
      } else {
        await _probe.check(node, generation, accept,
            timeout: node.signature == NodeEndpoint.shield.signature
                ? const Duration(seconds: 15)
                : const Duration(seconds: 2));
      }
    } catch (error) {
      trace.event('probe_error',
          {'generation': generation, 'type': error.runtimeType.toString()});
    } finally {
      trace.event('probe_end', {
        'route': node.diagnosticCode ?? 'custom',
        'generation': generation,
        'durationMs': clock.elapsedMilliseconds
      });
    }
  }

  void finishHandoff(String destination) {
    if (!ready || handoffComplete) return;
    handoffComplete = true;
    _retry?.cancel();
    _retryLogin = null;
    loginRecoveryVisible = false;
    sdkRecoveryVisible = false;
    _retrySdk = null;
    _publish(state.value.health?.fullyHealthy == true
        ? StartupStage.ready
        : StartupStage.degraded);
    trace.event(destination == 'home' ? 'home_entered' : 'login_entered');
  }

  void sdkFailed(Future<void> Function() retry) {
    if (_closed || handoffComplete) return;
    sdkRecoveryVisible = true;
    _retrySdk = retry;
    trace.event('sdk_initialization_failed');
    state.value = StartupState(StartupStage.unavailable,
        generation: _generation,
        health: state.value.health,
        showDetails: true,
        showActions: true);
  }

  void loginFailed(Future<void> Function() retry) {
    if (_closed || handoffComplete) return;
    _retryLogin = retry;
    loginRecoveryVisible = true;
    state.value = StartupState(StartupStage.unavailable,
        generation: _generation, health: state.value.health, showDetails: true);
    _retry?.cancel();
    _loginFailures++;
    final seconds = min(30, 3 * pow(2, min(_loginFailures - 1, 4)).toInt());
    _retry = Timer(
        Duration(
            milliseconds: (seconds * 1000 * (0.8 + 0.2 * _jitter())).round()),
        _resumeLogin);
  }

  void _resumeLogin() {
    if (_closed ||
        handoffComplete ||
        _loginRetrying ||
        !_foreground ||
        !_transport.online ||
        _retryLogin == null) {
      return;
    }
    _retry?.cancel();
    final action = _retryLogin!;
    _loginRetrying = true;
    unawaited(action().catchError((Object _) {
      loginFailed(action);
    }).whenComplete(() => _loginRetrying = false));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _transport.invalidateSnapshot();
    _environmentChanged();
    if (_foreground && (!ready || loginRecoveryVisible)) {
      unawaited(_refreshNetwork());
    }
  }

  @override
  void onClose() {
    _closed = true;
    _invalidate();
    _details?.cancel();
    _actions?.cancel();
    unawaited(_network?.cancel());
    if (!ready) unawaited(_cancelShield());
    WidgetsBinding.instance.removeObserver(this);
    state.dispose();
    super.onClose();
  }
}
