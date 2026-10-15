import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../conversation/drafts/conversation_draft_text.dart';
import '../../conversation/summary/conversation_latest_message_text.dart';

class GlobalSearchConversationSubtitle extends StatelessWidget {
  const GlobalSearchConversationSubtitle({
    super.key,
    required this.conversation,
  });

  final ConversationInfo conversation;

  static bool hasContent(ConversationInfo conversation) =>
      graphemeTrim(conversationDraftText(conversation.draftText) ?? '')
          .isNotEmpty ||
      graphemeTrim(conversationLatestMessageText(conversation)).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final draft = conversationDraftText(conversation.draftText) ?? '';
    if (graphemeTrim(draft).isEmpty) {
      return Text(
        conversationLatestMessageText(conversation),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: '[${StrRes.draftText}] ',
            style: TextStyle(color: Styles.c_FF381F)),
        TextSpan(text: draft.replaceAll(RegExp(r'[\r\n]+'), ' ')),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
