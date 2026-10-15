import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Structural send evidence, including before the SDK has created a message.
/// Do not pass filenames, asset identifiers, URLs, credentials or message text.
class ChatMediaDiagnostics {
  static void record(String stage,
      {String? traceID,
      String? messageID,
      String? outcome,
      Object? error,
      int? elapsedMs,
      int? count}) {
    if (!Logger().sdkIsInited) return;
    final code = error is PlatformException ? int.tryParse(error.code) : null;
    final event = <String, Object?>{
      'stage': stage,
      if (traceID != null) 'traceID': traceID,
      if (messageID != null) 'clientMsgID': messageID,
      if (outcome != null) 'outcome': outcome,
      if (elapsedMs != null) 'elapsedMs': elapsedMs,
      if (count != null) 'count': count,
      if (error != null) 'errorType': error.runtimeType.toString(),
      if (code != null) 'sdkCode': code,
      if (error is FileSystemException && error.osError != null)
        'osCode': error.osError!.errorCode,
    };
    unawaited(OpenIM.iMManager
        .logs(
          // Production is Info (4); the SDK method's default Debug (5) is lost.
          logLevel: 4,
          operationID: traceID ?? messageID,
          msgs: 'chat_media ${jsonEncode(event)}',
          keyAndValues: const [],
        )
        .timeout(const Duration(seconds: 2))
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }
}

class ChatMediaTrace {
  ChatMediaTrace()
      : id = 'media-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
  static int _sequence = 0;
  final String id;
  final _elapsed = Stopwatch()..start();
  String? messageID;

  void record(String stage, {String? outcome, Object? error, int? count}) =>
      ChatMediaDiagnostics.record(stage,
          traceID: id,
          messageID: messageID,
          outcome: outcome,
          error: error,
          count: count,
          elapsedMs: _elapsed.elapsedMilliseconds);

  Future<T> run<T>(String stage, Future<T> Function() action) async {
    record(stage, outcome: 'start');
    try {
      final value = await action();
      record(stage, outcome: 'complete');
      return value;
    } catch (error) {
      record(stage, outcome: 'failed', error: error);
      rethrow;
    }
  }
}
