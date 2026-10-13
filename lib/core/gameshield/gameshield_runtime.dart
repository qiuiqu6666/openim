import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gameshield_bridge/gameshield_bridge.dart';
import 'package:openim_common/openim_common.dart';
import '../server_nodes/node_endpoint.dart';
import '../server_nodes/startup_node_selection.dart';
import 'gameshield_failure.dart';
import 'gameshield_routes.dart';
import 'gameshield_settings.dart';

class GameShieldRuntime {
  GameShieldRuntime(
      {this.settings = GameShieldSettings.environment,
      this.startupTimeout = const Duration(seconds: 20),
      this.cleanupTimeout = const Duration(seconds: 5),
      GameShieldPlatform platform = const GameShieldBridge(),
      bool Function()? supportsPlatform,
      NodeEndpoint Function()? readOrigin})
      : _platform = platform,
        _supportsPlatform = supportsPlatform ??
            (() =>
                !kIsWeb &&
                const [TargetPlatform.android, TargetPlatform.iOS]
                    .contains(defaultTargetPlatform)),
        _readOrigin = readOrigin ?? NodeEndpoint.current;

  static final instance = GameShieldRuntime();
  final GameShieldSettings settings;
  final Duration startupTimeout, cleanupTimeout;
  final GameShieldPlatform _platform;
  final bool Function() _supportsPlatform;
  final NodeEndpoint Function() _readOrigin;
  Future<void>? _pending;
  bool _started = false;

  Future<void> prepare() {
    if (!settings.enabled || _started) return Future.value();
    return _pending ??= _prepare().whenComplete(() {
      _pending = null;
    });
  }

  Future<void> _prepare() async {
    if (!_supportsPlatform()) {
      throw const GameShieldFailure(GameShieldFailureKind.unsupportedPlatform);
    }
    if (!settings.licenseToken.startsWith('GS2.') ||
        !settings.auth.configured ||
        !settings.imApi.configured ||
        !settings.imWs.configured ||
        !settings.customerService.configured) {
      throw const GameShieldFailure(GameShieldFailureKind.configuration);
    }
    final origin = _readOrigin();
    // A production license must never inherit a user's custom deployment.
    if (origin.signature != NodeEndpoint.direct.signature ||
        settings.customerServiceBaseUrl
                .trim()
                .replaceFirst(RegExp(r'/+$'), '') !=
            Config.customerServiceOriginUrl) {
      throw const GameShieldFailure(GameShieldFailureKind.configuration);
    }
    try {
      final snapshot =
          await _platform.start(settings.licenseToken).timeout(startupTimeout);
      final route = GameShieldRoutes.resolve(settings, snapshot, origin);
      Config.useRuntimeNetworkRoute(route);
      _started = true;
      // Display only the protected process-local node. Do not run production
      // probes or persist ephemeral forwarding ports.
      StartupNodeSelection.last = NodeSelection(NodeEndpoint.current(), []);
    } catch (error) {
      try {
        await _platform.stop().timeout(cleanupTimeout);
      } catch (_) {}
      if (error is GameShieldFailure) rethrow;
      if (error is MissingPluginException ||
          (error is PlatformException && error.code == 'SDK_UNAVAILABLE')) {
        throw const GameShieldFailure(GameShieldFailureKind.unavailableSdk);
      }
      throw const GameShieldFailure(GameShieldFailureKind.startFailed);
    }
  }

  /// Stop only after every HTTP/IM consumer has been closed. The native client
  /// otherwise lives with the Flutter engine, including the logged-out screen.
  Future<void> close() async {
    try {
      await _pending;
    } catch (_) {
      // A failed preparation has already stopped its native client.
    }
    if (!_started) return;
    await _platform.stop();
    _started = false;
    Config.useRuntimeNetworkRoute(null);
    StartupNodeSelection.last = null;
  }
}
