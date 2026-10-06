import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Owns native PiP for one live call. Native video rendering is never simulated.
class CallPictureInPictureController extends ChangeNotifier {
  CallPictureInPictureController({
    this.onRestore,
    this.onClosed,
    MethodChannel channel = const MethodChannel('openim_call_pip'),
    TargetPlatform? platform,
  })  : _channel = channel,
        _platform = platform ?? defaultTargetPlatform,
        _owner = ++_nextOwner {
    _owners[_channel.name] = this;
    _channel.setMethodCallHandler(_receive);
  }

  final VoidCallback? onRestore;
  final VoidCallback? onClosed;
  final MethodChannel _channel;
  final TargetPlatform _platform;
  final int _owner;
  static int _nextOwner = 0;
  static final Map<String, CallPictureInPictureController> _owners = {};
  bool _disposed = false;
  bool _enabled = false;
  bool _supported = false;
  bool _active = false;
  bool _entering = false;
  bool _backgroundCameraSupported = false;
  int _generation = 0;
  String? _session;
  Timer? _entryTimer;

  bool get supported => _supported;
  bool get active => _active;
  bool get entering => _entering;
  bool get backgroundCameraSupported => _backgroundCameraSupported;
  bool get _mobile =>
      !kIsWeb &&
      (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS);

  Future<bool> configure({
    required bool enabled,
    String? remoteVideoTrackId,
    int aspectWidth = 9,
    int aspectHeight = 16,
    Rect? sourceRect,
  }) async {
    if (_disposed || !_mobile) return false;
    if (!enabled) {
      await stop();
      return false;
    }
    if (!_enabled) _session = '$_owner:${++_generation}';
    _enabled = true;
    final session = _session;
    final response = await _invoke<Map<dynamic, dynamic>>('configure', {
      'session': session,
      'enabled': true,
      'remoteVideoTrackId': remoteVideoTrackId,
      'aspectWidth': aspectWidth > 0 ? aspectWidth : 9,
      'aspectHeight': aspectHeight > 0 ? aspectHeight : 16,
      if (sourceRect != null)
        'sourceRect': {
          'left': sourceRect.left,
          'top': sourceRect.top,
          'right': sourceRect.right,
          'bottom': sourceRect.bottom,
        },
    });
    if (_disposed || !_enabled || session != _session) return false;
    _supported = response?['supported'] == true;
    _backgroundCameraSupported = response?['backgroundCameraSupported'] == true;
    if (!_supported) {
      _entryTimer?.cancel();
      _enabled = false;
      _session = null;
      _active = false;
      _entering = false;
      // A stopped video source may still have a native callback in flight.
      // Retire this session before disarming it so that callback cannot remount.
      if (session != null) {
        unawaited(_invoke<bool>('stop', {'session': session}));
      }
    }
    _notify();
    return _supported && response?['ready'] == true;
  }

  Future<bool> enter() async {
    if (_disposed || !_enabled || !_supported || _entering || _active) {
      return _active;
    }
    final session = _session;
    _entering = true;
    _watchEntry(session);
    _notify();
    final accepted = await _invoke<bool>('enter', {'session': session});
    if (_disposed || session != _session) return false;
    if (accepted != true) {
      _entryTimer?.cancel();
      _entering = false;
      _notify();
    }
    return accepted == true;
  }

  /// Stops only this call's PiP. Programmatic shutdown never invokes onClosed.
  Future<void> stop() async {
    if (_disposed) return;
    final session = _session;
    _enabled = false;
    _session = null;
    _entryTimer?.cancel();
    _active = false;
    _entering = false;
    _notify();
    if (_mobile && session != null) {
      await _invoke<bool>('stop', {'session': session});
    }
  }

  Future<void> _receive(MethodCall call) async {
    if (_disposed || !_enabled || call.method != 'state') return;
    final args = call.arguments;
    if (args is! Map || args['session'] != _session) return;
    switch (args['phase']) {
      case 'entering':
        _entering = true;
        _watchEntry(_session);
        break;
      case 'active':
        _entryTimer?.cancel();
        _active = true;
        _entering = false;
        break;
      case 'restored':
        final wasInPip = _active || _entering;
        _entryTimer?.cancel();
        _active = false;
        _entering = false;
        _notify();
        if (wasInPip) onRestore?.call();
        return;
      case 'closed':
        _entryTimer?.cancel();
        _active = false;
        _entering = false;
        _enabled = false;
        _session = null;
        _notify();
        onClosed?.call();
        return;
      case 'failed':
        _entryTimer?.cancel();
        _active = false;
        _entering = false;
        break;
      default:
        return;
    }
    _notify();
  }

  Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel
          .invokeMethod<T>(method, args)
          .timeout(const Duration(seconds: 2));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on TimeoutException {
      return null;
    } on TypeError {
      // An incompatible native plugin must fail capability negotiation safely.
      return null;
    }
  }

  void _watchEntry(String? session) {
    _entryTimer?.cancel();
    _entryTimer = Timer(const Duration(seconds: 3), () {
      if (_disposed || session != _session || _active || !_entering) return;
      _entering = false;
      _notify();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    final session = _session;
    _disposed = true;
    _enabled = false;
    _session = null;
    _entryTimer?.cancel();
    if (identical(_owners[_channel.name], this)) {
      _owners.remove(_channel.name);
      _channel.setMethodCallHandler(null);
      if (_mobile && session != null) {
        unawaited(_invoke<bool>('stop', {'session': session}));
      }
    }
    super.dispose();
  }
}
