import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Debug-only, metadata-only diagnostics shared by wallet entry and transport.
/// Never logs request/response bodies, credentials, amounts or error messages.
class WalletLoadLog {
  WalletLoadLog._(this.stage, this.details, bool watchPending)
      : id = ++_nextID {
    event('start');
    if (watchPending) {
      _pending = Timer(const Duration(seconds: 5), () => event('pending'));
    }
  }

  static int _nextID = 0;
  final int id;
  final String stage;
  final Map<String, Object?> details;
  final _elapsed = Stopwatch()..start();
  Timer? _pending;
  bool _finished = false;

  static WalletLoadLog? start(String stage,
          {Map<String, Object?> details = const {},
          bool watchPending = false}) =>
      kDebugMode ? WalletLoadLog._(stage, details, watchPending) : null;

  static void note(String stage, String event,
      [Map<String, Object?> details = const {}]) {
    if (kDebugMode) _write({'stage': stage, 'event': event, ...details});
  }

  static WalletLoadLog? request({
    required String method,
    required String url,
    required String path,
    required String operationID,
    required bool hasToken,
  }) {
    if (!kDebugMode ||
        method != 'GET' ||
        !const {'/chat/fund/pay-password', '/chat/fund/balances'}
            .contains(path)) {
      return null;
    }
    final uri = Uri.tryParse(url);
    return start('http', watchPending: true, details: {
      'method': method,
      'path': path,
      // Drop user-info, query and fragment even for a misconfigured URL.
      if (uri != null) 'server': '${uri.scheme}://${uri.host}:${uri.port}',
      'operationID': operationID,
      'hasToken': hasToken,
    });
  }

  void event(String name, [Map<String, Object?> fields = const {}]) {
    if (_finished) return;
    _write({
      'id': id,
      'stage': stage,
      'event': name,
      'elapsedMs': _elapsed.elapsedMilliseconds,
      ...details,
      ...fields,
    });
  }

  void response(Response<dynamic> response) {
    final body = response.data;
    final data = body is Map ? body['data'] : null;
    finish('response', {
      'httpStatus': response.statusCode,
      if (body is Map && body['errCode'] is num) 'errCode': body['errCode'],
      'bodyType': '${body.runtimeType}',
      'dataType': '${data.runtimeType}',
      if (details['path'] == '/chat/fund/pay-password') ...{
        'dataEmpty': data is Map && data.isEmpty,
        'setPresent': data is Map && data.containsKey('set'),
        'setIsBool': data is Map && data['set'] is bool,
        if (data is Map && data['set'] is bool) 'passwordSet': data['set'],
      },
    });
  }

  void error(Object error) {
    final response = error is DioException ? error.response : null;
    final body = response?.data;
    event('error', {
      'errorType': '${error.runtimeType}',
      if (error is DioException) 'networkType': error.type.name,
      if (response != null) 'httpStatus': response.statusCode,
      if (body is Map && body['errCode'] is num) 'errCode': body['errCode'],
      if (error is (int, String)) 'errCode': error.$1,
    });
  }

  void finish(String name, [Map<String, Object?> fields = const {}]) {
    event(name, fields);
    _finished = true;
    _pending?.cancel();
    _elapsed.stop();
  }

  static void _write(Map<String, Object?> fields) {
    try {
      debugPrint('[WalletLoad] ${jsonEncode(fields)}');
    } catch (_) {
      // Diagnostics cannot change authentication or request outcomes.
    }
  }
}
