import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import '../server_nodes/startup_node_selection.dart';
import '../server_nodes/node_endpoint.dart';
import '../server_nodes/node_availability_probe.dart';
import '../server_nodes/route_history.dart';
import 'youmeng_configuration.dart';

class YoumengRuntime {
  static const enabled =
      bool.fromEnvironment('YOUMENG_ENABLED', defaultValue: true);
  static const _channel = MethodChannel('openim/youmeng');

  static Future<void> prepare({void Function()? onShieldStarting}) async {
    Future<void> startShield() async {
      onShieldStarting?.call();
      await _startShield();
    }

    Config.useRuntimeNetworkRoute(null);
    final current = NodeEndpoint.current();
    NodeEndpoint? previous;
    try {
      previous = await RouteHistory.read();
    } catch (_) {}
    if (enabled &&
        previous == NodeEndpoint.shield &&
        NodeEndpoint.builtIn
            .any((node) => node.signature == current.signature)) {
      await prepareRememberedShield(
        startShield: startShield,
        checkDirect: () => StartupNodeSelector(apply: (_) async {}).select(),
        applyDirect: StartupNodeSelector.persist,
      );
      return;
    }
    await prepareWithFallback(
      shieldEnabled: enabled,
      select: () async {
        StartupNodeSelection.last =
            await StartupNodeSelector(preferred: previous).select();
        return StartupNodeSelection.last!;
      },
      startShield: startShield,
    );
  }

  /// The direct probe is read-only: a late result cannot overwrite shield.
  static Future<void> prepareRememberedShield({
    required Future<void> Function() startShield,
    required Future<NodeSelection> Function() checkDirect,
    required Future<void> Function(NodeEndpoint) applyDirect,
  }) async {
    final shield = Future.sync(startShield);
    final direct = Future.sync(checkDirect).then<NodeSelection?>((selection) {
      StartupNodeSelection.last = selection;
      return selection;
    }, onError: (Object _) => null);
    try {
      await shield;
      // Do not delay launch waiting for a blocked direct route.
    } catch (_) {
      final selection = await direct;
      if (selection == null ||
          !selection.checks.any((check) =>
              check.available &&
              check.endpoint.signature == selection.selected.signature)) {
        rethrow;
      }
      await applyDirect(selection.selected);
    }
  }

  /// Select direct routes before starting any native shield resources.
  static Future<void> prepareWithFallback({
    required bool shieldEnabled,
    required Future<NodeSelection> Function() select,
    required Future<void> Function() startShield,
  }) async {
    final selection = await select();
    final isBuiltIn = NodeEndpoint.builtIn
        .any((node) => node.signature == selection.selected.signature);
    if (!shieldEnabled ||
        !isBuiltIn ||
        selection.checks.isEmpty ||
        selection.checks.any((check) => check.available)) {
      return;
    }
    await startShield();
  }

  static Future<void> _startShield() async {
    await ensureReady();
    applyShieldRoute();
  }

  static void applyShieldRoute() {
    Config.useRuntimeNetworkRoute(const RuntimeNetworkRoute(
        authUrl: 'http://127.0.0.1:10008',
        apiUrl: 'http://127.0.0.1:10002',
        wsUrl: 'ws://127.0.0.1:10001',
        customerServiceUrl: 'http://127.0.0.1:8815'));
  }

  static Future<void>? _starting;
  static Future<void> ensureReady() =>
      _starting ??= _ensureReady().whenComplete(() {
        _starting = null;
      });

  static Future<void> _ensureReady() async {
    final configuration = await YoumengConfiguration.load();
    final cp = configuration.cp;
    final token = configuration.token;
    final key = configuration.key;
    const customer = String.fromEnvironment('CUSTOMER_SERVICE_BASE_URL',
        defaultValue: Config.customerServiceOriginUrl);
    final uri = Uri.tryParse(cp);
    if ((!Platform.isAndroid && !Platform.isIOS) ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        token.isEmpty ||
        !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(key)) {
      throw StateError('网络保护配置不完整或平台不支持');
    }
    if (customer != Config.customerServiceOriginUrl) {
      throw StateError('当前服务器不适用此网络保护配置');
    }
    final ready = await _channel
        .invokeMethod<bool>('start', {'cp': cp, 'token': token, 'key': key});
    if (ready != true) throw StateError('网络保护未就绪');
    if (!(await NodeAvailabilityProbe().check(NodeEndpoint.shield)).available) {
      throw StateError('网络保护业务链路未就绪');
    }
  }
}
