import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';

import '../../../chat/chat_logic.dart';
import '../../../chat/messages/widgets/chat_message_tile.dart';
import '../../history/ai_openim_message_text.dart';
import '../../theme/ai_palette.dart';
import 'ai_assistant_text.dart';
import 'ai_openim_custom_message.dart';

/// Changes the official account's presentation without replacing SDK messages.
class AiOpenIMMessageTile extends StatelessWidget {
  const AiOpenIMMessageTile(
      {super.key, required this.logic, required this.message, this.query = ''});

  final ChatLogic logic;
  final Message message;
  final String query;

  @override
  Widget build(BuildContext context) {
    // Repeated server friend notices add no content to an assistant exchange.
    if (message.contentType ==
            MessageType.friendApplicationApprovedNotification ||
        message.contentType == MessageType.typing) {
      return const SizedBox.shrink();
    }
    return ChatMessageTile(
      logic: logic,
      message: message,
      copyText: aiOpenimMessageText(message),
      leftAvatar: const AiAssistantAvatar(size: AiMetrics.dimension44),
      textContentBuilder: (context, message) {
        if (message.sendID == OpenIM.iMManager.userID) {
          return AiHighlightText(
            text: aiOpenimMessageText(message),
            query: query,
            style: const TextStyle(
                color: AiPalette.text,
                fontSize: AiMetrics.font15,
                height: AiMetrics.userTextLineHeight),
          );
        }
        return AiAssistantMarkdown(
          dark: Theme.of(context).brightness == Brightness.dark,
          text: aiOpenimMessageText(message),
          query: query,
          fileCache: const {},
          // Replies have ordinary OpenIM image messages, not gateway file IDs.
          onNeedFile: (_) {},
        );
      },
      customTypeBuilder: buildAiOpenIMCustomMessage,
    );
  }
}
