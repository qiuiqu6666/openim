import 'dart:async';
import 'dart:convert';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

/// Structural release diagnostics; excludes message bodies and credentials.
class ChatReadDiagnostics {
  ChatReadDiagnostics(this.conversationID);
  final String conversationID;
  static int _nextInstance = 0;
  final int instance = ++_nextInstance;
  final Map<String, String> _last = {};
  void record(String event, Map<String, Object?> state,
      {bool deduplicate = false}) {
    if (!Logger().sdkIsInited) return;
    final encoded = jsonEncode(state);
    if (deduplicate && _last[event] == encoded) return;
    if (deduplicate) _last[event] = encoded;
    unawaited(OpenIM.iMManager
        .logs(
            msgs: 'chat_read ${jsonEncode({
              'conversationID': conversationID,
              'instance': instance,
              'event': event,
              'time': DateTime.now().toIso8601String(),
              ...state,
            })}')
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }
}
