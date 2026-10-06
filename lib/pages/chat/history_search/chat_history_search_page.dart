import 'package:flutter/widgets.dart';

import 'chat_history_category.dart';
import 'chat_history_results_page.dart';
import 'chat_history_search_source.dart';
import 'navigation/chat_history_message_navigation.dart';
import 'selection/chat_history_sender_source.dart';

/// Shared entry for single-chat settings, group settings and global search.
class ChatHistorySearchPage extends StatelessWidget {
  const ChatHistorySearchPage({
    super.key,
    required this.conversationID,
    this.initialQuery = '',
    this.filesOnly = false,
    this.isGroup = false,
    this.source,
    this.senderSource,
    this.messageNavigation,
  });

  final String conversationID;
  final String initialQuery;
  final bool filesOnly;
  final bool isGroup;
  final ChatHistorySearchSource? source;
  final ChatHistorySenderSource? senderSource;
  final ChatHistoryMessageNavigation? messageNavigation;

  @override
  Widget build(BuildContext context) => ChatHistoryResultsPage(
        conversationID: conversationID,
        category: filesOnly ? ChatHistoryCategory.file : null,
        initialQuery: initialQuery,
        isGroup: isGroup,
        source: source,
        senderSource: senderSource,
        messageNavigation: messageNavigation,
      );
}
