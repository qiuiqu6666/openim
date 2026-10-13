import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

/// Evict only the opposite end of a contiguous history range. Pending sends
/// remain attached to their original objects so retries keep working.
List<Message> trimChatHistoryWindow(List<Message> messages,
    {required bool older, int limit = 600}) {
  bool pending(Message m) =>
      m.status == MessageStatus.sending || m.status == MessageStatus.failed;
  final persisted = messages.where((m) => !pending(m)).toList();
  if (persisted.length <= limit) return messages;
  final retained =
      (older ? persisted.take(limit) : persisted.skip(persisted.length - limit))
          .toSet();
  return messages.where((m) => pending(m) || retained.contains(m)).toList();
}
