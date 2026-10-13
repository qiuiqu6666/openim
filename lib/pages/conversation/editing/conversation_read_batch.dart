import 'dart:async';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Bounded workers; a timeout retires its worker because native work may live on.
Future<int> runConversationReadBatch({
  required List<ConversationInfo> conversations,
  required bool Function() isCurrent,
  required Future<void> Function(ConversationInfo) markRead,
  required void Function(int done, int total) progress,
}) async {
  final seen = <String>{};
  final targets = conversations
      .where((c) =>
          c.unreadCount > 0 &&
          c.conversationID.isNotEmpty &&
          seen.add(c.conversationID))
      .toList();
  var next = 0, done = 0, failed = 0;
  progress(0, targets.length);
  Future<void> worker() async {
    while (isCurrent() && next < targets.length) {
      final target = targets[next++];
      var timedOut = false;
      for (var attempt = 0; attempt < 2 && isCurrent(); attempt++) {
        try {
          await markRead(target);
          break;
        } on TimeoutException {
          failed++;
          timedOut = true;
          break;
        } catch (_) {
          if (attempt == 1) failed++;
        }
      }
      if (!isCurrent()) return;
      progress(++done, targets.length);
      if (timedOut) return;
    }
  }

  await Future.wait(List.generate(3, (_) => worker()));
  return failed + targets.length - next;
}
