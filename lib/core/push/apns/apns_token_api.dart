import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

class ApnsTokenApiException implements Exception {
  const ApnsTokenApiException(this.code, this.message,
      {this.statusCode, this.isCancelled = false});

  final String code;
  final String message;
  final int? statusCode;
  final bool isCancelled;

  @override
  String toString() => message;
}

/// Uses a captured IM identity, including when that identity is signing out.
/// An injected client's adapter is borrowed; its headers and observers are not.
class ApnsTokenApi {
  ApnsTokenApi({
    required String baseUrl,
    required String imToken,
    required this.userID,
    required String deviceID,
    Dio? client,
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        imToken = imToken.trim(),
        deviceID = deviceID.trim(),
        _ownsAdapter = client == null,
        _client = Dio(BaseOptions(
          connectTimeout: requestTimeout,
          sendTimeout: requestTimeout,
          receiveTimeout: requestTimeout,
          followRedirects: false,
          maxRedirects: 0,
        )) {
    if (client != null) {
      _client.httpClientAdapter = client.httpClientAdapter;
    }
  }

  static const requestTimeout = Duration(seconds: 5);

  static String normalizeBaseUrl(String value) {
    final base = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw ArgumentError('Invalid APNs service address');
    }
    return base.replaceFirst(RegExp(r'/+$'), '');
  }

  final String baseUrl;
  final String imToken;
  final String userID;
  final String deviceID;
  final Dio _client;
  final bool _ownsAdapter;
  final _requests = <CancelToken>{};
  bool _closed = false;

  Future<void> register({
    required String token,
    required String bundleId,
    required String apsEnvironment,
    CancelToken? cancelToken,
  }) async {
    final pushToken = token.trim();
    final environment = apsEnvironment.trim();
    if (pushToken.isEmpty || pushToken.contains(RegExp(r'[\r\n]'))) {
      throw const ApnsTokenApiException('TOKEN_INVALID', 'APNs token 无效');
    }
    if (!const {'development', 'production'}.contains(environment)) {
      throw const ApnsTokenApiException('CONFIG_INVALID', 'APNs 推送环境无效');
    }
    final response = await _request(
        '/third/set_push_token',
        {
          'platformID': 1,
          'deviceID': deviceID,
          'provider': 'apns',
          'token': pushToken,
          'environment': environment,
        },
        cancelToken);
    final payload = _acknowledgement(response);
    if (payload['deviceID'] != deviceID) {
      throw ApnsTokenApiException('INVALID_RESPONSE', 'APNs 注册未获确认',
          statusCode: response.statusCode);
    }
  }

  Future<void> delete({CancelToken? cancelToken}) async {
    final response = await _request('/third/delete_push_token',
        {'platformID': 1, 'deviceID': deviceID}, cancelToken);
    final payload = _acknowledgement(response);
    final removed = payload['removed'];
    if (removed is! int ||
        removed < 0 ||
        (payload.containsKey('deviceID') && payload['deviceID'] != deviceID)) {
      throw ApnsTokenApiException('INVALID_RESPONSE', 'APNs 解绑未获确认',
          statusCode: response.statusCode);
    }
  }

  Map<String, dynamic> _acknowledgement(Response<dynamic> response) {
    final envelope = _map(response.data);
    final code = envelope?['errCode'];
    final data = envelope?['data'];
    final payload = data is Map ? _map(data) : null;
    if (code is! int ||
        code != 0 ||
        envelope?['ok'] == false ||
        payload == null ||
        payload['ok'] == false ||
        payload['userID'] != userID ||
        payload['platformID'] is! int ||
        payload['platformID'] != 1) {
      throw ApnsTokenApiException('INVALID_RESPONSE', 'APNs 回执身份或数据无效',
          statusCode: response.statusCode);
    }
    return payload;
  }

  Future<Response<dynamic>> _request(
      String path, Map<String, dynamic> body, CancelToken? caller) async {
    if (_closed) {
      throw const ApnsTokenApiException('CANCELLED', 'APNs token 接口已关闭',
          isCancelled: true);
    }
    if (imToken.isEmpty ||
        imToken.contains(RegExp(r'[\r\n]')) ||
        userID.isEmpty ||
        userID.trim() != userID) {
      throw const ApnsTokenApiException('AUTH_INVALID', 'APNs 注册需要有效登录');
    }
    if (deviceID.isEmpty) {
      throw const ApnsTokenApiException('DEVICE_INVALID', 'APNs 注册需要设备标识');
    }
    if (caller?.isCancelled == true) throw caller!.cancelError!;
    final cancellation = CancelToken();
    _requests.add(cancellation);
    caller?.whenCancel.then((_) {
      if (_requests.contains(cancellation)) {
        cancellation.cancel('APNs token request cancelled');
      }
    });
    try {
      final response = await _client.request<dynamic>(
        '$baseUrl$path',
        data: body,
        cancelToken: cancellation,
        options: Options(
          method: 'POST',
          headers: {
            'token': imToken,
            'operationID': const Uuid().v4(),
          },
          contentType: Headers.jsonContentType,
          followRedirects: false,
          maxRedirects: 0,
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode;
      if (status == null || status < 200 || status >= 300) {
        throw ApnsTokenApiException('HTTP_ERROR', 'APNs token 请求未成功',
            statusCode: status);
      }
      return response;
    } finally {
      _requests.remove(cancellation);
    }
  }

  static Map<String, dynamic>? _map(dynamic raw) {
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } on FormatException {
        return null;
      }
    }
    if (raw is! Map || raw.keys.any((key) => key is! String)) return null;
    return raw.cast<String, dynamic>();
  }

  void close({bool force = true}) {
    if (_closed) return;
    _closed = true;
    for (final cancellation in _requests.toList()) {
      cancellation.cancel('APNs token API closed');
    }
    if (_ownsAdapter) _client.close(force: force);
  }
}
