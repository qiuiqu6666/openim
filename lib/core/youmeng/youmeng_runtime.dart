import 'dart:io';
import 'package:flutter/services.dart';
import 'package:openim_common/openim_common.dart';
import '../server_nodes/startup_node_selection.dart';

class YoumengRuntime {
  static const enabled = bool.fromEnvironment('YOUMENG_ENABLED');
  static const _channel = MethodChannel('openim/youmeng');

  static Future<void> prepare() async {
    if (!enabled) return StartupNodeSelection.prepare();
    const cp = String.fromEnvironment('YOUMENG_CP');
    const token = String.fromEnvironment('YOUMENG_TOKEN');
    const key = String.fromEnvironment('YOUMENG_AES_KEY');
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
    if (customer != Config.customerServiceOriginUrl ||
        Config.appAuthUrl != 'http://127.0.0.1:10008' ||
        Config.imApiUrl != 'http://127.0.0.1:10002' ||
        Config.imWsUrl != 'ws://127.0.0.1:10001') {
      throw StateError('当前服务器不适用此网络保护配置');
    }
    final ready = await _channel
        .invokeMethod<bool>('start', {'cp': cp, 'token': token, 'key': key});
    if (ready != true) throw StateError('网络保护未就绪');
    Config.useRuntimeNetworkRoute(const RuntimeNetworkRoute(
        authUrl: 'http://127.0.0.1:10008',
        apiUrl: 'http://127.0.0.1:10002',
        wsUrl: 'ws://127.0.0.1:10001',
        customerServiceUrl: 'http://127.0.0.1:8815'));
  }
}
