import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Routing UI only: the bridge never receives playback credentials.
class LiveCastService {
  const LiveCastService({
    MethodChannel channel = const MethodChannel('openim_group_live_cast'),
  }) : _channel = channel;

  final MethodChannel _channel;

  Future<void> openSystemPicker({TargetPlatform? platform}) async {
    if (kIsWeb ||
        (platform ?? defaultTargetPlatform) != TargetPlatform.android) {
      throw const LiveCastFailure('当前设备不支持应用内投屏，请使用系统投屏功能');
    }
    try {
      final opened = await _channel.invokeMethod<bool>('openCastSettings');
      if (opened != true) throw const LiveCastFailure.unavailable();
    } on LiveCastFailure {
      rethrow;
    } catch (_) {
      throw const LiveCastFailure.unavailable();
    }
  }
}

class LiveCastFailure implements Exception {
  const LiveCastFailure(this.message);
  const LiveCastFailure.unavailable() : message = '无法打开投屏设置，请从系统控制中心使用投屏功能';

  final String message;

  @override
  String toString() => message;
}
