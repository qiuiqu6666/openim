import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../controller/im_controller.dart';
import '../im_callback.dart';
import '../network/transport_state.dart';
import '../youmeng/youmeng_runtime.dart';
import 'manual_node_switch_runtime.dart';
import 'manual_node_switch_service.dart';
import 'node_endpoint.dart';
import 'timed_node_probe.dart';
import 'node_availability_probe.dart';
import 'direct_recovery_policy.dart';
import 'route_history.dart';
import 'feedback/network_recovery_progress.dart';

/// Foreground recovery; shares the manual switch lock and SDK session owner.
class AutomaticNodeRuntime extends GetxService with WidgetsBindingObserver {
  AutomaticNodeRuntime(
      {this.startupReady,
      this.networkChanges,
      Future<List<ConnectivityResult>> Function()? networkSnapshot,
      this.switchService,
      this.probeNodes,
      this.shieldEnabled = YoumengRuntime.enabled})
      : _networkSnapshot = networkSnapshot ??
            (networkChanges == null ? Connectivity().checkConnectivity : null);
  final bool Function()? startupReady;
  final Stream<List<ConnectivityResult>>? networkChanges;
  final Future<List<ConnectivityResult>> Function()? _networkSnapshot;
  final ManualNodeSwitchService? switchService;
  final Future<List<NodeAvailability>> Function(List<NodeEndpoint>, bool)?
      probeNodes;
  final bool shieldEnabled;
  Timer? _timer;
  StreamSubscription<dynamic>? _status, _network;
  bool _closed = false, _busy = false;
  bool _freshCheckPending = false, _failureReported = false;
  final _transport = NetworkTransportState();
  ManualNodeSwitchService get _switchService =>
      switchService ?? ManualNodeSwitchRuntime.instance;
  int _revision = 0, _failures = 0;
  final _directRecovery = DirectRecoveryPolicy();
  Object? _recoverySession;
  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    final im = Get.find<IMController>();
    _status = im.imSdkStatusPublishSubject.listen((event) {
      if (event.status == IMSdkStatus.syncEnded &&
          DataSp.userID != null &&
          !_switchService.busy) {
        unawaited(RouteHistory.remember(NodeEndpoint.current()));
      }
      if (event.status == IMSdkStatus.connectionSucceeded) {
        _failureReported = false;
      }
      if (event.status == IMSdkStatus.connectionFailed ||
          event.status == IMSdkStatus.connecting) {
        // Repeated native reconnect callbacks must not defeat route backoff.
        if (!_failureReported) {
          _failureReported = true;
          _schedule(Duration.zero);
        }
      }
    });
    _network = (networkChanges ?? Connectivity().onConnectivityChanged).listen(
        (values) {
      if (!_transport.update(values)) return;
      _environmentChanged();
    }, onError: (Object _) {});
    _schedule(const Duration(seconds: 5));
    unawaited(_refreshTransport());
  }

  Future<void> _refreshTransport() async {
    final read = _networkSnapshot;
    if (read == null || _closed || !_foreground) return;
    final changed = await _transport.refresh(read);
    if (changed && !_closed && _foreground) _environmentChanged();
  }

  void _schedule(Duration delay) {
    if (_closed || _busy) return;
    _timer?.cancel();
    if (_foreground && _transport.online) _timer = Timer(delay, _check);
  }

  Future<void> _check() async {
    if (_closed || _busy || !_foreground || !_transport.online) return;
    _freshCheckPending = false;
    if (startupReady?.call() == false) {
      _schedule(const Duration(seconds: 1));
      return;
    }
    final user = DataSp.userID, token = DataSp.imToken;
    final session = (user, token, DataSp.chatToken);
    if (_recoverySession != session) {
      _directRecovery.reset();
      _recoverySession = session;
    }
    if (user == null || token == null) {
      _schedule(const Duration(seconds: 5));
      return;
    }
    final current = NodeEndpoint.current();
    if (![...NodeEndpoint.builtIn, NodeEndpoint.shield]
        .any((node) => node.signature == current.signature)) {
      _schedule(const Duration(seconds: 30));
      return;
    }
    final revision = _revision;
    bool active() =>
        !_closed &&
        _foreground &&
        _transport.online &&
        revision == _revision &&
        DataSp.userID == user &&
        DataSp.imToken == token &&
        DataSp.chatToken == session.$3 &&
        NodeEndpoint.current().signature == current.signature;
    _busy = true;
    var healthy = false;
    try {
      final service = _switchService;
      if (service.busy || !service.canSwitch()) return;
      // A healthy shield must not short-circuit slower direct probes.
      final onShield = current.signature == NodeEndpoint.shield.signature;
      if (!onShield) _directRecovery.reset();
      final nodes = [
        current,
        ...NodeEndpoint.builtIn
            .where((node) => node.signature != current.signature)
      ];
      final checks = probeNodes != null
          ? await probeNodes!(nodes, onShield)
          : onShield
              ? await Future.wait(nodes.map((node) => NodeAvailabilityProbe(
                      timeout: const Duration(milliseconds: 2250))
                  .check(node)))
              : await TimedNodeProbe().check(nodes);
      if (!active()) return;
      if (checks.first.available) {
        healthy = true;
        if (onShield) {
          final direct = _directRecovery.observe(checks, DateTime.now());
          if (direct != null) {
            try {
              await service.switchTo(direct,
                  isActive: active, allowShield: true);
              _directRecovery.reset();
            } catch (_) {
              _directRecovery.failed(DateTime.now());
              rethrow;
            }
          }
        }
        return;
      }
      NodeEndpoint? target;
      for (final check in checks.skip(1)) {
        if (check.available) {
          target = check.endpoint;
          break;
        }
      }
      if (target == null && shieldEnabled) {
        target = NodeEndpoint.shield;
      }
      if (target == null) return;
      // The shield's tunnel and OpenIM already own retries on this route.
      // A brief failed probe must not log out/reinitialize the same session.
      if (target.signature == current.signature) return;
      // switchTo verifies all three services again, checks session ownership,
      // serializes reconnect and restores the old route on login failure.
      final feedback = target == NodeEndpoint.shield
          ? NetworkRecoveryProgress.instance.begin(
              NetworkRecoveryStage.startingShield,
              context: NetworkRecoveryContext.reconnect)
          : null;
      try {
        await service.switchTo(target, isActive: active, allowShield: true);
      } finally {
        feedback?.close();
      }
      healthy = true;
    } catch (error) {
      healthy = false;
      Logger.print('Automatic route recovery: ${error.runtimeType}');
    } finally {
      _busy = false;
      if (healthy) _failures = 0;
      const retry = [2, 4, 8, 15, 30];
      final seconds = healthy ? 30 : retry[_failures];
      if (!healthy && _failures < retry.length - 1) _failures++;
      _schedule(
          _freshCheckPending ? Duration.zero : Duration(seconds: seconds));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _environmentChanged();
    if (_foreground) unawaited(_refreshTransport());
    if (!_foreground) _transport.invalidateSnapshot();
  }

  void _environmentChanged() {
    _revision++;
    _freshCheckPending = true;
    _failures = 0;
    _failureReported = false;
    _directRecovery.reset();
    _timer?.cancel();
    _schedule(Duration.zero);
  }

  @override
  void onClose() {
    _closed = true;
    _transport.invalidateSnapshot();
    _revision++;
    _timer?.cancel();
    unawaited(_status?.cancel());
    unawaited(_network?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
