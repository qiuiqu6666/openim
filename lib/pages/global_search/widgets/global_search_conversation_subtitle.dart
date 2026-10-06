import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../conversation/drafts/conversation_draft_text.dart';

class GlobalSearchConversationSubtitle extends StatelessWidget {
  const GlobalSearchConversationSubtitle({
    super.key,
    required this.conversation,
  });

  final ConversationInfo conversation;

  @override
  Widget build(BuildContext context) {
    final draft = conversationDraftText(conversation.draftText)?.trim();
    if (draft == null || draft.isEmpty) {
      return Text(
        conversation.isGroupChat ? StrRes.globalSearchGroup : StrRes.singleChat,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Text.rich(
      TextSpan(children: [
        TextSpan(
            text: '[${StrRes.draftText}] ',
            style: TextStyle(color: Styles.c_FF381F)),
        TextSpan(text: draft.replaceAll(RegExp(r'[\r\n]+'), ' ')),
      ]),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppTokens.textSecondary(dark: dark),
          ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
