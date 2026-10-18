import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Only fixed route templates and generated request IDs enter diagnostic logs.
abstract final class OrganizerRequestDiagnostics {
  static Future<T> run<T>({
    required String route,
    required String source,
    required String operationID,
    required Future<T> Function() request,
    int? Function()? businessCode,
  }) async {
    final watch = Stopwatch()..start();
    try {
      return await request();
    } catch (error) {
      final record = jsonEncode({
        'event': 'organizer_request_failed',
        'route': route,
        'source': source,
        'operationID': operationID,
        'elapsedMs': watch.elapsedMilliseconds,
        'type': error is DioException
            ? error.type.name
            : error.runtimeType.toString(),
        if (businessCode?.call() != null) 'businessCode': businessCode!(),
        if (error is DioException) 'httpStatus': error.response?.statusCode,
      });
      // Logger.print is disabled in release; retain this sanitized event there.
      developer.log(record, name: '99Chat.RequestDiagnostics');
      if (Logger().sdkIsInited) unawaited(_writeNative(record));
      rethrow;
    }
  }

  static Future<void> _writeNative(String record) async {
    try {
      await OpenIM.iMManager.logs(msgs: record, keyAndValues: []);
    } catch (_) {
      // Logging must never replace the original failure or trigger feedback.
    }
  }
}
