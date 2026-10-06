import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../../chat/chat_logic.dart';
import '../../../chat/messages/widgets/chat_message_tile.dart';
import '../../localization/ai_assistant_i18n.dart';
import '../../history/ai_openim_message_text.dart';
import '../../theme/ai_palette.dart';
import 'ai_assistant_text.dart';

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
      customTypeBuilder: _custom,
    );
  }

  CustomTypeInfo? _custom(BuildContext context, Message message) {
    final custom = message.customElem;
    if (custom == null ||
        !['image', 'groupCard'].contains(custom.description)) {
      return null;
    }
    dynamic data = custom.data;
    try {
      data = jsonDecode(custom.data ?? '');
    } on FormatException {
      // The image prompt is also allowed to be a plain string.
    }
    if (data is String) {
      try {
        data = jsonDecode(data);
      } on FormatException {
        // Keep the prompt string.
      }
    }
    final i18n = AiAssistantI18n.of(context);
    final isImage = custom.description == 'image';
    final title = isImage
        ? i18n.t(zhHans: '生成图片', en: 'Generate image')
        : i18n.t(zhHans: '总结群聊', en: 'Summarize group chat');
    final detail = isImage
        ? (data is Map ? data['prompt']?.toString() ?? '' : data.toString())
        : (data is Map
            ? (data['groupName'] ?? data['groupID'] ?? '').toString()
            : '');
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomTypeInfo(Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(isImage ? Icons.image_outlined : Icons.notes_outlined,
              size: AiMetrics.dimension18, color: AiPalette.brand(dark)),
          const SizedBox(width: AiMetrics.space8),
          Flexible(
              child: Text(title,
                  style: TextStyle(
                      color: AiPalette.primary(dark),
                      fontSize: AiMetrics.font14,
                      fontWeight: FontWeight.w600))),
        ]),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: AiMetrics.space8),
          Text(detail,
              style: TextStyle(
                  color: AiPalette.primary(dark),
                  fontSize: AiMetrics.font14,
                  height: AiMetrics.textLineHeight)),
        ],
      ],
    ));
  }
}
