import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import 'conversation_read_request.dart';

/// Finite recovery using only IDs seen before a failed full read. The SDK's
/// conversation-wide API has no cutoff and must not be replayed after leaving.
class ConversationReadRecovery {
  static const retryDelay = Duration(milliseconds: 750);
  static const _batchSize = 100;

  Future<void> recover(ConversationReadRequest request,
      {required bool Function() isCurrent}) async {
    final ids = request.retryMessageIDs;
    bool current() => request.isCurrent && isCurrent();
    for (var offset = 0; offset < ids.length; offset += _batchSize) {
      final batch = ids.skip(offset).take(_batchSize).toList(growable: false);
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!current()) return;
        try {
          // This existing SDK path updates only these messages and decrements
          // their unread contribution. Private/burn messages are never queued.
          // ignore: deprecated_member_use
          await OpenIM.iMManager.messageManager.markMessagesAsReadByMsgID(
              conversationID: request.conversationID, messageIDList: batch);
          break;
        } catch (_) {
          if (!current()) return;
          if (attempt == 1) rethrow;
          await Future<void>.delayed(retryDelay);
        }
      }
    }
  }
}
