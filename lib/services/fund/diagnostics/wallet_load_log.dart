import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart' show Logger;

/// Metadata-only diagnostics shared by wallet entry and transport. Password
/// setup/write diagnostics also run in release for physical-device support.
/// Never logs request/response bodies, credentials, amounts or error messages.
class WalletLoadLog {
  WalletLoadLog._(this.stage, this.details, bool watchPending,
      {bool passwordDiagnostic = false})
      : _passwordDiagnostic = passwordDiagnostic,
        id = ++_nextID {
    event('start');
    if (watchPending) {
      _pending = Timer(const Duration(seconds: 5), () => event('pending'));
    }
  }

  static int _nextID = 0;
  final int id;
  final String stage;
  final Map<String, Object?> details;
  final bool _passwordDiagnostic;
  final _elapsed = Stopwatch()..start();
  Timer? _pending;
  bool _finished = false;

  static WalletLoadLog? start(String stage,
          {Map<String, Object?> details = const {},
          bool watchPending = false}) =>
      kDebugMode ? WalletLoadLog._(stage, details, watchPending) : null;

  static WalletLoadLog passwordSetup() =>
      WalletLoadLog._('setup', const {}, true, passwordDiagnostic: true);

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
    final passwordWrite = method == 'PUT' && path == '/chat/fund/pay-password';
    if (!passwordWrite &&
        (!kDebugMode ||
            method != 'GET' ||
            !const {'/chat/fund/pay-password', '/chat/fund/balances'}
                .contains(path))) {
      return null;
    }
    final uri = Uri.tryParse(url);
    return WalletLoadLog._(
        'http',
        {
          'method': method,
          'path': path,
          // Drop user-info, query and fragment even for a misconfigured URL.
          if (uri != null) 'server': '${uri.scheme}://${uri.host}:${uri.port}',
          'operationID': operationID,
          'hasToken': hasToken,
        },
        true,
        passwordDiagnostic: passwordWrite);
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
    }, passwordDiagnostic: _passwordDiagnostic);
  }

  void response(Response<dynamic> response) {
    final body = response.data;
    final data = body is Map ? body['data'] : null;
    final fields = <String, Object?>{
      'httpStatus': response.statusCode,
      if (body is Map && body['errCode'] is num) 'errCode': body['errCode'],
      'bodyType': '${body.runtimeType}',
      'dataType': '${data.runtimeType}',
      if (details['method'] == 'GET' &&
          details['path'] == '/chat/fund/pay-password') ...{
        'dataEmpty': data is Map && data.isEmpty,
        'setPresent': data is Map && data.containsKey('set'),
        'setIsBool': data is Map && data['set'] is bool,
        if (data is Map && data['set'] is bool) 'passwordSet': data['set'],
      },
    };
    // Keep writes open until parsing completes, so a malformed response is
    // distinguishable from an HTTP/network failure and a successful write.
    if (_passwordDiagnostic) {
      event('response', fields);
    } else {
      finish('response', fields);
    }
  }

  void error(Object error) {
    final response = error is DioException ? error.response : null;
    final body = response?.data;
    event('error', {
      'errorType': '${error.runtimeType}',
      if (error is DioException) 'networkType': error.type.name,
      if (response != null) 'httpStatus': response.statusCode,
      if (response != null) 'bodyType': '${body.runtimeType}',
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

  static void _write(Map<String, Object?> fields,
      {bool passwordDiagnostic = false}) {
    try {
      final prefix = passwordDiagnostic ? '[TradePassword]' : '[WalletLoad]';
      final message = '$prefix ${jsonEncode({
            if (passwordDiagnostic) ...{
              'platform': defaultTargetPlatform.name,
              'buildMode': kReleaseMode
                  ? 'release'
                  : (kProfileMode ? 'profile' : 'debug'),
            },
            ...fields,
          })}';
      // General app debug output is disabled in release. Only this narrow,
      // metadata-only diagnostic bypasses that switch.
      if (passwordDiagnostic && kReleaseMode) {
        debugPrintSynchronously(message);
      } else {
        debugPrint(message);
      }
      if (passwordDiagnostic && Logger().sdkIsInited) {
        unawaited(OpenIM.iMManager
            .logs(
              msgs: message,
              // Native SDK expects a JSON array, even without extra fields.
              keyAndValues: const [],
              operationID: fields['operationID'] as String?,
            )
            .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
      }
    } catch (_) {
      // Diagnostics cannot change authentication or request outcomes.
    }
  }
}
