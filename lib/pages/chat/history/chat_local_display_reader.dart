import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../history_search/chat_history_search_source.dart';

/// Display-only local rows; never establishes latest-window or paging state.
Future<List<Message>> readChatLocalDisplay(ConversationInfo conversation) async {
  final manager = OpenIM.iMManager.messageManager;
  if (conversation.isPrivateChat != true) {
    return manager.getLocalHistorySnapshot(
        conversationID: conversation.conversationID, allowIncomplete: true);
  }
  // Native snapshots reject an entire private conversation. Its older ordinary
  // messages are still safe to display; query SQLite and exclude private rows.
  final rows = await OpenIMChatHistorySearchSource().search(
      conversationID: conversation.conversationID,
      query: const ChatHistorySearchQuery(),
      pageIndex: 1,
      count: 40);
  return rows
      .where((m) => m.attachedInfoElem?.isPrivateChat != true)
      .toList();
}
