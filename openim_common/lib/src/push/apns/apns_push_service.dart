import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef PushRequest = Future<void> Function(String endpoint, String credential,
    String action, Map<String, dynamic> data);

/// Owns the native APNs registration for exactly one authenticated session.
/// Tokens stay in memory; Apple supplies a fresh token on every registration.
class ApnsPushService with WidgetsBindingObserver {
  ApnsPushService({
    required this.request,
    required this.currentSession,
    required this.deviceID,
    this.channel = const MethodChannel('openim_apns'),
    this.onError,
  });

  final PushRequest request;
  final ({String userID, String credential, String endpoint})? Function()
      currentSession;
  final Future<String> Function() deviceID;
  final MethodChannel channel;
  final void Function(Object)? onError;
  ({String userID, String credential, String endpoint})? _owner;
  String? _device;
  Map<String, dynamic>? _token;
  Future<void> _queue = Future<void>.value();
  Timer? _retry;
  int _generation = 0;
  int _failures = 0;
  bool _observing = false;

  bool _owns(int generation) =>
      _owner != null && generation == _generation && currentSession() == _owner;

  Future<void> login(String userID) async {
    final owner = currentSession();
    if (owner == null || owner.userID != userID) return;
    final generation = ++_generation;
    _retry?.cancel();
    _owner = owner;
    _token = null;
    _device = null;
    _failures = 0;
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
      channel.setMethodCallHandler(_onNativeEvent);
    }
    try {
      final id = await deviceID();
      if (!_owns(generation)) return;
      _device = id;
      await _register(generation);
    } catch (error) {
      _failed(error, generation);
    }
  }

  Future<void> _register(int generation) async {
    if (!_owns(generation)) return;
    try {
      final token = await channel.invokeMapMethod<String, dynamic>('register');
      if (_owns(generation) && token != null) _accept(token, generation);
    } catch (error) {
      _failed(error, generation);
    }
  }

  Future<dynamic> _onNativeEvent(MethodCall call) async {
    final generation = _generation;
    if (!_owns(generation)) return;
    if (call.method == 'tokenChanged' && call.arguments is Map) {
      _accept(Map<String, dynamic>.from(call.arguments as Map), generation);
    } else if (call.method == 'registrationFailed') {
      _failed(StateError('APNs registration failed'), generation);
    }
  }

  void _accept(Map<String, dynamic> token, int generation) {
    final value = token['token'];
    final environment = token['environment'];
    if (value is! String ||
        !RegExp(r'^[0-9a-fA-F]{8,200}$').hasMatch(value) ||
        value.length.isOdd ||
        (environment != 'development' && environment != 'production')) {
      _failed(StateError('Invalid APNs registration'), generation);
      return;
    }
    _token = {'token': value, 'environment': environment};
    unawaited(_bind(generation));
  }

  Future<void> _bind(int generation) {
    final owner = _owner;
    final token = _token;
    final device = _device;
    if (!_owns(generation) ||
        owner == null ||
        token == null ||
        device == null) {
      return Future<void>.value();
    }
    // Serialize registration and deletion. A slow upload must not complete
    // after logout deletion or rebind an old account after an account switch.
    return _enqueue(() async {
      if (!_owns(generation)) return;
      try {
        await request(owner.endpoint, owner.credential, 'set_push_token', {
          'platformID': 1,
          'deviceID': device,
          'provider': 'apns',
          ...token,
        });
        if (_owns(generation)) {
          _failures = 0;
          _retry?.cancel();
        }
      } catch (error) {
        _failed(error, generation);
      }
    });
  }

  void _failed(Object error, int generation) {
    if (!_owns(generation)) return;
    onError?.call(error);
    _retry?.cancel();
    if (++_failures > 5) return;
    _retry = Timer(Duration(seconds: _failures * 10), () {
      if (!_owns(generation)) return;
      unawaited(_token == null ? _register(generation) : _bind(generation));
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _owns(_generation)) {
      _failures = 0;
      // Refresh the backend TTL and retry permission/network changes.
      unawaited(_register(_generation));
    }
  }

  Future<void> logout() async {
    final owner = _owner;
    final device = _device;
    ++_generation;
    _owner = null;
    _token = null;
    _device = null;
    _retry?.cancel();
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      channel.setMethodCallHandler(null);
      _observing = false;
    }
    // Enqueue deletion before any await allows a new session to register.
    final deletion = _enqueue(() async {
      if (owner == null || device == null) return;
      try {
        await request(owner.endpoint, owner.credential, 'delete_push_token', {
          'platformID': 1,
          'deviceID': device,
        });
      } catch (error) {
        onError?.call(error);
      }
    });
    try {
      await channel.invokeMethod<void>('unregister');
    } catch (error) {
      onError?.call(error);
    }
    await deletion;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _queue.then((_) => operation(), onError: (_) => operation());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }
}
