import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../../../core/conversation_reads/conversation_read_request.dart';
import 'conversation_batch_read_api.dart';

/// Projects only acknowledged previews captured before the batch began.
/// Native receipt notifications remain the durable SDK/aggregate source.
class ConversationBatchReadProjection {
  ConversationBatchReadProjection(Iterable<ConversationInfo> rows)
      : _captured = {
          for (final row in rows)
            row.conversationID: ConversationReadRequest.capture(row),
        };

  final Map<String, ConversationReadRequest> _captured;

  bool confirm(List<BatchReadTarget> targets, Iterable<ConversationInfo> rows,
      void Function(ConversationReadRequest) remember) {
    final requests = <String, ConversationReadRequest>{};
    for (final target in targets) {
      final request = _captured[target.conversationID];
      if (request != null &&
          request.isCurrent &&
          (request.messageSequence ?? 0) > 0 &&
          request.messageSequence! <= target.hasReadSeq) {
        request.complete(true);
        remember(request);
        requests[target.conversationID] = request;
      }
    }
    var changed = false;
    for (final row in rows) {
      if (row.unreadCount > 0 &&
          (requests[row.conversationID]?.canClear(row) ?? false)) {
        row.unreadCount = 0;
        changed = true;
      }
    }
    return changed;
  }
}
