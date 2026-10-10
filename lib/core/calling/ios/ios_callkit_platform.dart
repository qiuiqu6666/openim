import 'dart:async';

import 'package:flutter/services.dart';

import '../../push/apns/apns_platform.dart';

abstract interface class IOSCallKitPlatform {
  Stream<Map<String, dynamic>> get events;
  Stream<APNsDeviceToken> get tokens;
  Future<void> initialize();
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]);
  Future<void> dispose();
}

/// PushKit and CallKit share one native owner, independent of message APNs.
class MethodChannelIOSCallKitPlatform implements IOSCallKitPlatform {
  MethodChannelIOSCallKitPlatform({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('ios_voip_callkit');

  final MethodChannel _channel;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _tokens = StreamController<APNsDeviceToken>.broadcast();
  Future<void>? _initializing;
  bool _closed = false;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Stream<APNsDeviceToken> get tokens => _tokens.stream;

  @override
  Future<void> initialize() {
    if (_closed) return Future<void>.value();
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
      if (call.method == 'onEvent') {
        _acceptEvent(call.arguments);
      } else if (call.method == 'onVoipToken') {
        final token = decodeToken(call.arguments);
        if (token != null) _tokens.add(token);
      }
    });
    await _channel.invokeMethod<void>('install');
    if (_closed) return;
    await _channel.invokeMethod<void>('setEventHandlerReady', {'ready': true});
    if (_closed) return;
    final pending =
        await _channel.invokeListMethod<Object?>('drainPendingEvents');
    if (_closed) return;
    for (final event in pending ?? const []) {
      _acceptEvent(event);
    }
  }

  static APNsDeviceToken? decodeToken(Object? raw) {
    if (raw is! Map) return null;
    return APNsDeviceToken.decode({
      'apnsToken': raw['voipToken'],
      'bundleId': raw['bundleId'],
      'apsEnvironment': raw['apsEnvironment'],
    });
  }

  void _acceptEvent(Object? raw) {
    if (_closed || raw is! Map || raw.keys.any((key) => key is! String)) {
      return;
    }
    _events.add(Map<String, dynamic>.from(raw));
  }

  @override
  Future<T?> invoke<T>(String method, [Map<String, dynamic>? arguments]) async {
    if (_closed) return null;
    await initialize();
    if (_closed) return null;
    return _channel.invokeMethod<T>(method, arguments);
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    _channel.setMethodCallHandler(null);
    await _events.close();
    await _tokens.close();
  }
}
