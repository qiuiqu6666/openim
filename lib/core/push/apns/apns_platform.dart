import 'dart:async';

import 'package:flutter/services.dart';

/// APNs tokens belong to an app/device, and are kept in memory only.
class APNsDeviceToken {
  const APNsDeviceToken({
    required this.token,
    required this.bundleID,
    required this.environment,
  });

  final String token, bundleID, environment;

  static APNsDeviceToken? decode(Object? value) {
    if (value is! Map) return null;
    final token = value['apnsToken'] ?? value['token'];
    final bundle = value['bundleId'];
    final environment = value['apsEnvironment'];
    if (token is! String ||
        !RegExp(r'^(?:[0-9a-fA-F]{2})+$').hasMatch(token) ||
        bundle is! String ||
        bundle.trim().isEmpty ||
        environment is! String ||
        !const {'development', 'production'}.contains(environment)) {
      return null;
    }
    return APNsDeviceToken(
      token: token.toLowerCase(),
      bundleID: bundle,
      environment: environment,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is APNsDeviceToken &&
      token == other.token &&
      bundleID == other.bundleID &&
      environment == other.environment;

  @override
  int get hashCode => Object.hash(token, bundleID, environment);
}

abstract class APNsPlatform {
  Stream<APNsDeviceToken> get tokens;
  Stream<Map<String, dynamic>> get notificationTaps;
  Stream<int> get registrationErrors => const Stream<int>.empty();
  Future<void> initialize();
  Future<void> activateNotificationTaps();
  Future<bool> register();
  Future<APNsDeviceToken?> currentToken();
  Future<void> unregister();
  Future<void> dispose();
}

/// Direct Apple notification registration; Firebase is not used on this path.
class MethodChannelAPNsPlatform implements APNsPlatform {
  MethodChannelAPNsPlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('ios_apns_push');

  final MethodChannel _channel;
  final _tokens = StreamController<APNsDeviceToken>.broadcast();
  final _taps = StreamController<Map<String, dynamic>>.broadcast();
  final _errors = StreamController<int>.broadcast();
  Future<void>? _initializing;
  bool _closed = false;

  @override
  Stream<APNsDeviceToken> get tokens => _tokens.stream;
  @override
  Stream<Map<String, dynamic>> get notificationTaps => _taps.stream;
  @override
  Stream<int> get registrationErrors => _errors.stream;

  @override
  Future<void> initialize() {
    final pending = _initializing;
    if (pending != null) return pending;
    late final Future<void> initialization;
    initialization = _initialize().catchError((Object error) {
      if (identical(_initializing, initialization)) _initializing = null;
      throw error;
    });
    _initializing = initialization;
    return initialization;
  }

  Future<void> _initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (_closed) return;
      if (call.method == 'onApnsToken') {
        final token = APNsDeviceToken.decode(call.arguments);
        if (token != null) _tokens.add(token);
      } else if (call.method == 'onNotificationTap') {
        _acceptTap(call.arguments);
      } else if (call.method == 'onRegistrationError') {
        final arguments = call.arguments;
        if (arguments is Map && arguments['code'] is int) {
          _errors.add(arguments['code'] as int);
        }
      }
    });
    await _channel.invokeMethod<void>('install');
    if (_closed) return;
    await _channel
        .invokeMethod<void>('setNotificationTapHandlerReady', {'ready': true});
    if (_closed) return;
    _acceptTap(
        await _channel.invokeMethod<Object?>('consumePendingNotificationTap'));
  }

  void _acceptTap(Object? value) {
    if (_closed || value is! Map) return;
    if (value.keys.any((key) => key is! String)) return;
    _taps.add(Map<String, dynamic>.from(value));
  }

  @override
  Future<void> activateNotificationTaps() async {
    if (_closed) return;
    await initialize();
    if (_closed) return;
    await _channel.invokeMethod<void>('activateNotificationTaps');
    if (_closed) return;
    _acceptTap(
        await _channel.invokeMethod<Object?>('consumePendingNotificationTap'));
  }

  @override
  Future<bool> register() async {
    if (_closed) return false;
    await activateNotificationTaps();
    if (_closed) return false;
    final response = await _channel
        .invokeMapMethod<String, dynamic>('registerForRemoteNotifications');
    return !_closed &&
        const {'authorized', 'provisional', 'ephemeral'}
            .contains(response?['authorizationStatus']);
  }

  @override
  Future<APNsDeviceToken?> currentToken() async => _closed
      ? null
      : APNsDeviceToken.decode(
          await _channel.invokeMethod<Object?>('getCachedTokens'));

  @override
  Future<void> unregister() async {
    if (_closed) return;
    await _channel.invokeMethod<void>('unregisterForRemoteNotifications');
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _channel.setMethodCallHandler(null);
    await _tokens.close();
    await _taps.close();
    await _errors.close();
  }
}
