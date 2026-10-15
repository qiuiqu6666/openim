import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

typedef RevocationLog = void Function(Map<String, Object?> event);

/// Release-visible evidence. Never include message text, tokens or raw errors.
class ChatRevocationTrace {
  ChatRevocationTrace({
    required String accountID,
    required String conversationID,
    required String? clientMsgID,
    required int? seq,
    RevocationLog? log,
  })  : _log = log ?? write,
        _identity = {
          'accountID': accountID,
          'conversationID': conversationID,
          'clientMsgID': clientMsgID,
          'seq': seq,
        };

  static int _sequence = 0;
  final String id =
      'revoke-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';
  final _watch = Stopwatch()..start();
  final Map<String, Object?> _identity;
  final RevocationLog _log;

  void record(String stage, {String? outcome, Object? error}) {
    try {
      _log({
        ..._identity,
        'operationID': id,
        'stage': stage,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'elapsedMs': _watch.elapsedMilliseconds,
        if (outcome != null) 'outcome': outcome,
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error is PlatformException) 'sdkCode': error.code,
      });
    } catch (_) {
      // Diagnostics must never prevent a recall or its user feedback.
    }
  }

  static void write(Map<String, Object?> event) {
    if (!Logger().sdkIsInited) return;
    unawaited(OpenIM.iMManager
        .logs(
          logLevel: 4,
          operationID: event['operationID'] as String,
          msgs: 'chat_revoke ${jsonEncode(event)}',
          keyAndValues: const [],
        )
        .timeout(const Duration(seconds: 2))
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }
}
