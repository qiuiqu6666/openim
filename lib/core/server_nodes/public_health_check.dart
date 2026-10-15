import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

/// Public liveness only; never evidence of login, RPC, gateway or sync health.
class PublicHealthCheck {
  static final _random = Random();

  /// Bounded jitter, at most 250ms early; retain existing retry ceilings.
  static Duration retryDelay(Duration base) =>
      base -
      Duration(
          milliseconds:
              _random.nextInt(min(250, base.inMilliseconds ~/ 10) + 1));

  static Future<String?>? _installedVersion;

  static Future<String?> _readInstalledVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      final value = build.isEmpty ? version : '$version+$build';
      return version.isNotEmpty &&
              RegExp(r'^[A-Za-z0-9._+\-]{1,80}$').hasMatch(value)
          ? value
          : null;
    } catch (_) {
      return null;
    }
  }

  /// Only call on a dedicated, caller-owned probe client.
  static void isolate(Dio client, Duration timeout) {
    client.interceptors.clear();
    client.options
      ..headers = {}
      ..queryParameters = {}
      ..connectTimeout = timeout
      ..receiveTimeout = timeout
      ..sendTimeout = timeout
      ..followRedirects = false;
  }

  static Future<Map<String, String>> diagnosticHeaders() async {
    String? version;
    try {
      version = await (_installedVersion ??= _readInstalledVersion())
          .timeout(const Duration(milliseconds: 250));
    } catch (_) {
      // Build information is optional and must not delay route recovery.
    }
    return {
      'operationID': 'line-probe-${const Uuid().v4()}',
      'X-Client-Source': 'line-probe',
      if (version != null) 'X-Client-Version': version,
    };
  }

  static Future<void> get(Dio client, String baseUrl,
      {required String service, required CancelToken cancelToken}) async {
    final base = Uri.parse(baseUrl.trim().replaceFirst(RegExp(r'/+$'), ''));
    if (!const {'http', 'https'}.contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const FormatException('Invalid health endpoint');
    }
    final response = await client.get<dynamic>('$base/healthz',
        cancelToken: cancelToken,
        options: Options(
            headers: await diagnosticHeaders(),
            followRedirects: false,
            responseType: ResponseType.json));
    final body = response.data;
    if (response.statusCode != 200 ||
        body is! Map ||
        body['status'] != 'ok' ||
        body['service'] != service ||
        (body.containsKey('errCode') && body['errCode'] != 0)) {
      throw StateError('Unexpected health response');
    }
  }
}
