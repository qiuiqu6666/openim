import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import 'youmeng_configuration.dart';
import 'shield_readiness.dart';
import 'native_shield_preparation.dart';

class YoumengRuntime {
  static const enabled =
      bool.fromEnvironment('YOUMENG_ENABLED', defaultValue: true);
  static const _channel = MethodChannel('openim/youmeng');

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
    await ensureNativeReady();
    await ShieldReadiness.verify();
  }

  static final _native = NativeShieldPreparation(
    startNative: _startNative,
    cancelNative: () => _channel.invokeMethod<void>('cancel'),
  );
  static Future<void> ensureNativeReady() => _native.prepare();
  static Future<void> cancelNativePreparation() => _native.cancel();

  static Future<void> _startNative(bool Function() isCurrent) async {
    final configuration = await YoumengConfiguration.load();
    if (!isCurrent()) throw StateError('Shield cancelled');
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
  }
}
