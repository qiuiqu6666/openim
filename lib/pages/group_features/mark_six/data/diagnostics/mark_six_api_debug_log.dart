import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../data/diagnostics/group_feature_api_diagnostics.dart';

/// Debug-only summaries: credentials, request bodies and business rows are omitted.
class MarkSixApiDebugLog implements GroupFeatureApiDiagnostics {
  static T trace<T>(T Function() action) => kDebugMode
      ? withGroupFeatureDiagnostics(action, () => MarkSixApiDebugLog())
      : action();

  static void event(String stage, Map<String, Object?> fields) {
    if (!kDebugMode) return;
    reportGroupFeatureDiagnostics(
        () => debugPrint('[六合彩API][$stage] ${jsonEncode(fields)}'));
  }

  final _watch = Stopwatch();
  String _operationID = '-';

  String _url(RequestOptions request) {
    // Query values and URL user-info can contain credentials; print neither.
    final uri = request.uri;
    return uri.replace(userInfo: '', query: '', fragment: '').toString();
  }

  Map<String, Object?> _requestFields(RequestOptions request) => {
        'operationID': _operationID,
        'method': request.method,
        'url': _url(request),
        'queryKeys': request.queryParameters.keys.toList(),
        'hasBearerToken': request.headers.entries.any((entry) =>
            entry.key.toLowerCase() == 'authorization' &&
            entry.value is String &&
            RegExp(r'^Bearer\s+\S+$', caseSensitive: false)
                .hasMatch(entry.value as String)),
      };

  @override
  void onRequest(RequestOptions request) {
    _operationID = '${request.headers['operationID'] ?? '-'}';
    _watch.start();
    event('请求', _requestFields(request));
  }

  @override
  void onResponse(Response<dynamic> response) {
    _watch.stop();
    final raw = response.data;
    final data = raw is Map ? raw['data'] ?? raw : raw;
    final code =
        raw is Map ? raw['errCode'] ?? raw['errorCode'] ?? raw['code'] : null;
    // Avoid printing arbitrary server text, including echoed credentials.
    final safeCode = code is num ||
            (code is String && RegExp(r'^[A-Z0-9_-]{1,32}$').hasMatch(code))
        ? code
        : null;
    event('响应', {
      ..._requestFields(response.requestOptions),
      'httpStatus': response.statusCode,
      'code': safeCode,
      'elapsedMs': _watch.elapsedMilliseconds,
      'dataType': '${data.runtimeType}',
      if (data is Map && data['bound'] is bool) 'bound': data['bound'],
      if (data is Map && data['enabled'] is bool) 'enabled': data['enabled'],
      if (data is List) 'itemCount': data.length,
    });
  }

  @override
  void onError(Object error) {
    _watch.stop();
    event('失败', {
      'operationID': _operationID,
      'errorType': '${error.runtimeType}',
      'elapsedMs': _watch.elapsedMilliseconds,
      if (error is DioException) ...{
        ..._requestFields(error.requestOptions),
        'networkError': error.type.name,
        'httpStatus': error.response?.statusCode,
      },
    });
  }

  @override
  void onStreamData(String chunk) {}

  @override
  void onStreamClosed() {}
}
