import 'dart:async';
import 'dart:convert';

import 'package:openim_common/openim_common.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

typedef HistoryDiagnostic = void Function(Map<String, Object?> event);

/// Write structural history evidence into native logs in release builds too.
/// Never record message bodies, credentials, or recipient profile data.
class ChatHistoryDiagnostics {
  static void record(String conversationID, Map<String, Object?> event) {
    if (!Logger().sdkIsInited) return;
    unawaited(OpenIM.iMManager
        .logs(
          keyAndValues: const [],
          msgs: 'chat_history ${jsonEncode({
                'conversationID': conversationID,
                ...event,
              })}',
        )
        .then<void>((_) {}, onError: (Object _, StackTrace __) {}));
  }
}
