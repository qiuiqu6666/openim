import 'package:flutter/services.dart';
import 'android_update_package.dart';

class AndroidDownloadStatus {
  const AndroidDownloadStatus(this.state, {this.bytes = 0, this.total = 0});
  final String state;
  final int bytes, total;
}

abstract class AndroidUpdatePlatform {
  Future<void> enqueue(AndroidUpdatePackage package);
  Future<AndroidDownloadStatus> status();
  Future<void> verify(AndroidUpdatePackage package);
  Future<void> clear();
  Future<bool> canInstall();
  Future<void> requestPermission();
  Future<void> install(AndroidUpdatePackage package);
}

class NativeAndroidUpdatePlatform implements AndroidUpdatePlatform {
  static const _channel = MethodChannel('openim/android_update');
  @override
  Future<void> enqueue(AndroidUpdatePackage package) =>
      _channel.invokeMethod('enqueue', package.arguments);
  @override
  Future<AndroidDownloadStatus> status() async {
    final data =
        await _channel.invokeMapMethod<String, dynamic>('status') ?? {};
    return AndroidDownloadStatus(data['state'] as String? ?? 'missing',
        bytes: (data['bytes'] as num?)?.toInt() ?? 0,
        total: (data['total'] as num?)?.toInt() ?? 0);
  }

  @override
  Future<void> verify(AndroidUpdatePackage package) =>
      _channel.invokeMethod('verify', package.arguments);
  @override
  Future<void> clear() => _channel.invokeMethod('clear');
  @override
  Future<bool> canInstall() async =>
      await _channel.invokeMethod<bool>('canInstall') ?? false;
  @override
  Future<void> requestPermission() => _channel.invokeMethod('permission');
  @override
  Future<void> install(AndroidUpdatePackage package) =>
      _channel.invokeMethod('install', package.arguments);
}
