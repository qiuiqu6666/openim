import 'package:flutter/services.dart';

class GameShieldEndpoint {
  const GameShieldEndpoint({
    required this.appId,
    required this.groupName,
    required this.host,
    required this.port,
    required this.protocol,
  });
  final String appId, groupName, host, protocol;
  final int port;

  factory GameShieldEndpoint.fromMap(Map<Object?, Object?> value) =>
      GameShieldEndpoint(
        appId: value['appId'] as String,
        groupName: value['groupName'] as String,
        host: value['host'] as String,
        port: value['port'] as int,
        protocol: value['protocol'] as String,
      );
}

class GameShieldSnapshot {
  const GameShieldSnapshot({
    required this.ready,
    required this.sdkVersion,
    required this.activeTunnels,
    required this.endpoints,
    this.tcpPorts = const {},
  });
  final bool ready;
  final String sdkVersion;
  final int activeTunnels;
  final List<GameShieldEndpoint> endpoints;

  /// Original configured TCP port to the SDK's actual listening port.
  final Map<int, int> tcpPorts;

  factory GameShieldSnapshot.fromMap(Map<Object?, Object?> value) =>
      GameShieldSnapshot(
        ready: value['ready'] as bool,
        sdkVersion: value['sdkVersion'] as String,
        activeTunnels: value['activeTunnels'] as int,
        tcpPorts: Map.unmodifiable(
          (value['tcpPorts'] as Map? ?? {}).map(
            (key, port) => MapEntry(int.parse(key as String), port as int),
          ),
        ),
        endpoints: List.unmodifiable(
          (value['endpoints'] as List).map(
            (item) => GameShieldEndpoint.fromMap(
              Map<Object?, Object?>.from(item as Map),
            ),
          ),
        ),
      );
}

abstract interface class GameShieldPlatform {
  Future<GameShieldSnapshot> start(String licenseToken);
  Future<GameShieldSnapshot> status();
  Future<void> stop();
}

/// Credentials are passed as channel arguments, never as logs or error details.
class GameShieldBridge implements GameShieldPlatform {
  const GameShieldBridge({
    MethodChannel channel = const MethodChannel('openim/gameshield'),
  }) : _channel = channel;
  final MethodChannel _channel;

  Future<GameShieldSnapshot> _snapshot(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (value == null) {
      throw PlatformException(code: 'INVALID_SNAPSHOT');
    }
    return GameShieldSnapshot.fromMap(value);
  }

  @override
  Future<GameShieldSnapshot> start(String licenseToken) => _snapshot('start', {
    'licenseToken': licenseToken,
    'autoChangePort': true,
  });
  @override
  Future<GameShieldSnapshot> status() => _snapshot('status');
  @override
  Future<void> stop() => _channel.invokeMethod<void>('stop');
}
