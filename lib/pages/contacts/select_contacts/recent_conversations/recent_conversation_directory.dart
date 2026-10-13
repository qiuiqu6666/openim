import 'dart:math' as math;

import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

class RecentConversationDirectoryResult {
  const RecentConversationDirectoryResult(this.rows, this.failed);
  final List<ConversationInfo> rows;
  final bool failed;
}

/// One failed membership check cannot discard unrelated chats. Bound native
/// queries and retain the original SDK order after independent checks finish.
class RecentConversationDirectory {
  const RecentConversationDirectory(this.isJoinedGroup);
  final Future<bool> Function(String) isJoinedGroup;

  Future<RecentConversationDirectoryResult> load(List<ConversationInfo> rows,
      {required bool Function(ConversationInfo) isVisible,
      required bool Function() isCurrent}) async {
    final results = List<ConversationInfo?>.filled(rows.length, null);
    var next = 0;
    var failed = false;
    Future<void> worker() async {
      while (isCurrent() && next < rows.length) {
        final index = next++;
        final row = rows[index];
        if (!isVisible(row) ||
            row.conversationType == ConversationType.notification) {
          continue;
        }
        try {
          if (!row.isGroupChat ||
              await isJoinedGroup(row.groupID!)
                  .timeout(const Duration(seconds: 5))) {
            if (isCurrent()) results[index] = row;
          }
        } catch (_) {
          if (isCurrent()) failed = true;
        }
      }
    }

    await Future.wait(List.generate(math.min(4, rows.length), (_) => worker()));
    return RecentConversationDirectoryResult(
        results.whereType<ConversationInfo>().toList(), failed);
  }
}
