import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:openim/pages/group_features/data/diagnostics/group_feature_api_diagnostics.dart';
import 'package:openim/pages/group_features/models/group_feature_context.dart';

import '../../utils/sangong_sse_parser.dart';

/// Console diagnostics for a single request or stream; never changes wire data.
class SangongApiDebugLog implements GroupFeatureApiDiagnostics {
  static SangongApiDebugLog? create() =>
      kDebugMode ? SangongApiDebugLog() : null;

  /// Includes shared prerequisites only when a Sangong entry refreshes them.
  static T trace<T>(T Function() action) =>
      kDebugMode ? withGroupFeatureDiagnostics(action, create) : action();

  /// Records the parsed permission and raw fields when no API is dispatched.
  static void permissionDenied(GroupFeatureContext context, String reason,
      {String? logicalTenantId, Map<String, dynamic>? config}) {
    if (!kDebugMode) return;
    reportGroupFeatureDiagnostics(() {
      final capability = context.capabilities.sangong;
      final feature = context.features.sangong;
      SangongApiDebugLog()._emit('权限检查', {
        'reason': reason,
        'groupID': context.groupID,
        'currentUserID': context.currentUserID,
        'capabilitiesUrl':
            '${context.api.baseUrl}${context.api.pathPrefix}/chat/groups/${Uri.encodeComponent(context.groupID)}/feature-capabilities',
        'capabilityVersion': context.capabilities.version,
        if (logicalTenantId != null) 'logicalTenantId': logicalTenantId,
        if (config != null) 'myConfig': config,
        'sangong': {
          'canConfigure': capability.canConfigure,
          'canManage': capability.canManage,
          'canOpenAgent': capability.canOpenAgent,
          'tenantID': capability.tenantID,
          'raw': capability.raw,
        },
        'groupFeatures': {
          'enabled': feature.enabled,
          'manageEntry': feature.manageEntry,
          'agentEntry': feature.agentEntry,
        },
      });
    });
  }

  static const _chunkSize = 800;
  static const _masked = '***';
  static const _sensitiveKeys = {
    'authorization',
    'proxyauthorization',
    'token',
    'chattoken',
    'imtoken',
    'refreshtoken',
    'accesstoken',
    'idtoken',
    'password',
    'passwd',
    'pwd',
    'secret',
    'clientsecret',
    'apisecret',
    'apikey',
    'xapikey',
    'cookie',
    'setcookie',
    'sessionkey',
    'sig',
    'sign',
    'signature',
  };
  final _elapsed = Stopwatch();
  final _knownSecrets = <String>{};
  final _parser = SangongSseParser();
  String _id = '-';
  bool _streamClosed = false;

  @override
  void onRequest(RequestOptions request) {
    if (!kDebugMode) return;
    _knownSecrets.clear();
    _rememberRequest(request);
    _parser.reset();
    _streamClosed = false;
    _elapsed
      ..reset()
      ..start();
    _emit('请求', {
      'method': request.method,
      'url': _requestUrl(request),
      'headers': request.headers,
      'body': request.data,
    });
  }

  @override
  void onResponse(Response<dynamic> response) {
    if (!kDebugMode) return;
    _rememberRequest(response.requestOptions);
    final streaming = response.data is ResponseBody;
    if (!streaming) _elapsed.stop();
    _emit('响应', {
      'method': response.requestOptions.method,
      'url': _requestUrl(response.requestOptions),
      'status': response.statusCode,
      'elapsedMs': _elapsed.elapsedMilliseconds,
      'data': streaming ? '<SSE流，未读取>' : response.data,
    });
  }

  @override
  void onError(Object error) {
    if (!kDebugMode) return;
    if (error is DioException) {
      _rememberRequest(error.requestOptions);
      _emit('异常', {
        'type': error.type.name,
        'method': error.requestOptions.method,
        'url': _requestUrl(error.requestOptions),
        'status': error.response?.statusCode,
        'elapsedMs': _elapsed.elapsedMilliseconds,
        'message': error.message,
        'error': error.error,
        if (error.response != null) 'data': error.response!.data,
      });
    } else {
      _emit('异常', {
        'type': '${error.runtimeType}',
        'elapsedMs': _elapsed.elapsedMilliseconds,
        'error': error,
      });
    }
  }

  @override
  void onStreamData(String chunk) {
    if (!kDebugMode || _streamClosed) return;
    _parser.feed(chunk, (event, data) {
      _emit('SSE事件', {'event': event, 'data': data});
    });
  }

  @override
  void onStreamClosed() {
    if (!kDebugMode || _streamClosed) return;
    _streamClosed = true;
    _elapsed.stop();
    _parser.reset();
    _emit('结束', {'elapsedMs': _elapsed.elapsedMilliseconds});
  }

  void _rememberRequest(RequestOptions request) {
    for (final header in request.headers.entries) {
      final key = header.key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
      if (key == 'operationid' && header.value != null) {
        _id = _string(header.value);
      }
      if (_isSensitiveKey(header.key)) _rememberSecret(header.value);
    }
    _rememberSensitiveValues(request.queryParameters, Set<Object>.identity());
    _rememberSensitiveValues(request.data, Set<Object>.identity());
  }

  void _rememberSensitiveValues(dynamic value, Set<Object> ancestors,
      {bool sensitive = false}) {
    if (value is String) {
      if (sensitive) _rememberSecret(value);
      final json = _structuredJson(value);
      if (json != null) {
        _rememberSensitiveValues(json, ancestors, sensitive: sensitive);
      }
      return;
    }
    if (value is! Map && value is! Iterable) return;
    if (!ancestors.add(value as Object)) return;
    try {
      if (value is Map) {
        for (final entry in value.entries) {
          _rememberSensitiveValues(entry.value, ancestors,
              sensitive: sensitive || _isSensitiveKey(_string(entry.key)));
        }
      } else {
        for (final item in value as Iterable) {
          _rememberSensitiveValues(item, ancestors, sensitive: sensitive);
        }
      }
    } finally {
      ancestors.remove(value);
    }
  }

  void _rememberSecret(dynamic value) {
    if (value is Iterable) {
      for (final item in value) {
        _rememberSecret(item);
      }
      return;
    }
    if (value is! String || value.trim().isEmpty) return;
    final secret = value.trim();
    _knownSecrets.add(secret);
    final credential =
        RegExp(r'^(?:Bearer|Basic)\s+(.+)$', caseSensitive: false)
            .firstMatch(secret)
            ?.group(1);
    if (credential != null && credential.isNotEmpty) {
      _knownSecrets.add(credential);
    }
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[-_\s]'), '');
    return _sensitiveKeys.contains(normalized) ||
        normalized.endsWith('token') ||
        normalized.endsWith('password') ||
        normalized.endsWith('secret') ||
        normalized.endsWith('signature');
  }

  static String _requestUrl(RequestOptions request) {
    try {
      return request.uri.toString();
    } catch (_) {
      return request.path;
    }
  }

  void _emit(String stage, dynamic value) {
    if (!kDebugMode) return;
    try {
      _rememberSensitiveValues(value, Set<Object>.identity());
      final sanitized = _sanitize(value, Set<Object>.identity());
      final text = const JsonEncoder.withIndent('  ').convert(sanitized);
      final points = text.runes.toList(growable: false);
      final count = (points.length + _chunkSize - 1) ~/ _chunkSize;
      final id = _maskString(_id);
      for (var index = 0; index < count; index++) {
        final start = index * _chunkSize;
        final end = start + _chunkSize < points.length
            ? start + _chunkSize
            : points.length;
        final part = String.fromCharCodes(points.sublist(start, end));
        debugPrint('[三公API][$id][$stage][${index + 1}/$count] $part');
      }
    } catch (_) {
      // Diagnostics must not change request completion or expose an unsanitized
      // payload when a custom object cannot be rendered.
    }
  }

  dynamic _sanitize(dynamic value, Set<Object> ancestors) {
    if (value == null || value is bool || value is int) return value;
    if (value is double) return value.isFinite ? value : '$value';
    if (value is ResponseBody) return '<SSE流，未读取>';
    if (value is String) {
      final json = _structuredJson(value);
      return json == null ? _maskString(value) : _sanitize(json, ancestors);
    }
    if (value is Map || value is Iterable) {
      if (!ancestors.add(value as Object)) return '<循环引用>';
      try {
        if (value is Map) {
          return <String, dynamic>{
            for (final entry in value.entries)
              _string(entry.key): _isSensitiveKey(_string(entry.key))
                  ? _masked
                  : _sanitize(entry.value, ancestors),
          };
        }
        return (value as Iterable)
            .map((item) => _sanitize(item, ancestors))
            .toList(growable: false);
      } finally {
        ancestors.remove(value);
      }
    }
    return _maskString(_string(value));
  }

  static dynamic _structuredJson(String value) {
    final trimmed = value.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map || decoded is List ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  String _maskString(String value) {
    var masked = value;
    // Replace longer credentials first so an overlapping shorter value cannot
    // leave the remainder of a token in an exception or plain-text response.
    final secrets = _knownSecrets.toList()
      ..sort((left, right) => right.length.compareTo(left.length));
    for (final secret in secrets) {
      masked = masked.replaceAll(secret, _masked);
      masked = masked.replaceAll(Uri.encodeComponent(secret), _masked);
      masked = masked.replaceAll(Uri.encodeQueryComponent(secret), _masked);
    }
    // URL fields can contain credentials unrelated to the current Chat token.
    // Change only the log copy and retain all ordinary query values.
    try {
      final uri = Uri.tryParse(masked);
      if (uri != null &&
          uri.hasAuthority &&
          const {'http', 'https'}.contains(uri.scheme) &&
          uri.hasQuery &&
          uri.queryParametersAll.keys.any(_isSensitiveKey)) {
        masked = uri.replace(queryParameters: {
          for (final entry in uri.queryParametersAll.entries)
            entry.key: _isSensitiveKey(entry.key) ? [_masked] : entry.value,
        }).toString();
      }
    } on FormatException {
      // A malformed URL can still be printed as sanitized diagnostic text.
    }
    return masked;
  }

  static String _string(dynamic value) {
    try {
      return '$value';
    } catch (_) {
      return '<无法格式化>';
    }
  }
}
