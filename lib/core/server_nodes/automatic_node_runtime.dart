import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../controller/im_controller.dart';
import '../im_callback.dart';
import '../youmeng/youmeng_runtime.dart';
import 'manual_node_switch_runtime.dart';
import 'node_endpoint.dart';
import 'timed_node_probe.dart';
import 'node_availability_probe.dart';
import 'direct_recovery_policy.dart';
import 'route_history.dart';

/// Foreground recovery; shares the manual switch lock and SDK session owner.
class AutomaticNodeRuntime extends GetxService with WidgetsBindingObserver {
  Timer? _timer;
  StreamSubscription<dynamic>? _status, _network;
  bool _closed = false, _busy = false, _online = true;
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
          !ManualNodeSwitchRuntime.instance.busy) {
        unawaited(RouteHistory.remember(NodeEndpoint.current()));
      }
      if (event.status == IMSdkStatus.connectionFailed ||
          event.status == IMSdkStatus.connecting) {
        _schedule(Duration.zero);
      }
    });
    _network = Connectivity().onConnectivityChanged.listen((values) {
      _online = values.any((value) => value != ConnectivityResult.none);
      _revision++;
      _directRecovery.reset();
      _schedule(Duration.zero);
    }, onError: (Object _) {});
    _schedule(const Duration(seconds: 5));
  }

  void _schedule(Duration delay) {
    if (_closed || _busy) return;
    _timer?.cancel();
    if (_foreground && _online) _timer = Timer(delay, _check);
  }

  Future<void> _check() async {
    if (_closed || _busy || !_foreground || !_online) return;
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
        _online &&
        revision == _revision &&
        DataSp.userID == user &&
        DataSp.imToken == token;
    _busy = true;
    var healthy = false;
    try {
      final service = ManualNodeSwitchRuntime.instance;
      if (service.busy || !service.canSwitch()) return;
      // A healthy shield must not short-circuit slower direct probes.
      final onShield = current.signature == NodeEndpoint.shield.signature;
      if (!onShield) _directRecovery.reset();
      final nodes = [
        current,
        ...NodeEndpoint.builtIn
            .where((node) => node.signature != current.signature)
      ];
      final checks = onShield
          ? await Future.wait(nodes.map((node) =>
              NodeAvailabilityProbe(timeout: const Duration(milliseconds: 2250))
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
      if (target == null && YoumengRuntime.enabled) {
        await YoumengRuntime.ensureReady();
        if (!active()) return;
        target = NodeEndpoint.shield;
      }
      if (target == null) return;
      // switchTo verifies all three services again, checks session ownership,
      // serializes reconnect and restores the old route on login failure.
      await service.switchTo(target, isActive: active, allowShield: true);
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
      _schedule(Duration(seconds: seconds));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _revision++;
    _directRecovery.reset();
    _timer?.cancel();
    if (_foreground) _schedule(Duration.zero);
  }

  @override
  void onClose() {
    _closed = true;
    _revision++;
    _timer?.cancel();
    unawaited(_status?.cancel());
    unawaited(_network?.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
