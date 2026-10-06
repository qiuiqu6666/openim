import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_history_category.dart';
import '../chat_history_search_strings.dart';
import '../chat_history_search_tokens.dart';

/// Persistent content shortcuts above conversation search results.
class ChatHistorySearchShortcuts extends StatelessWidget {
  const ChatHistorySearchShortcuts({
    super.key,
    required this.isGroup,
    required this.onSelected,
  });

  final bool isGroup;
  final ValueChanged<ChatHistoryCategory> onSelected;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primaryText = AppTokens.textPrimary(dark: dark);
    final secondaryText = AppTokens.textSecondary(dark: dark);
    final shortcuts = <(ChatHistoryCategory, IconData, String)>[
      (
        ChatHistoryCategory.media,
        Icons.photo_outlined,
        chatHistorySearchText(context, 'media'),
      ),
      (ChatHistoryCategory.file, Icons.folder_outlined, StrRes.file),
      if (isGroup) ...[
        (
          ChatHistoryCategory.date,
          Icons.calendar_today_outlined,
          chatHistorySearchText(context, 'date'),
        ),
        (
          ChatHistoryCategory.sender,
          Icons.person_outline,
          chatHistorySearchText(context, 'groupMembers'),
        ),
      ],
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        ChatHistorySearchTokens.horizontalPadding,
        ChatHistorySearchTokens.shortcutTopPadding,
        ChatHistorySearchTokens.horizontalPadding,
        ChatHistorySearchTokens.shortcutBottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            chatHistorySearchText(context, 'specified'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: ChatHistorySearchTokens.shortcutHeadingFontSize,
              color: secondaryText,
            ),
          ),
          const SizedBox(height: ChatHistorySearchTokens.shortcutHeadingGap),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: ChatHistorySearchTokens.shortcutSpacing,
            runSpacing: ChatHistorySearchTokens.shortcutRunSpacing,
            children: shortcuts.map((shortcut) {
              final (category, icon, label) = shortcut;
              return Semantics(
                button: true,
                label: label,
                onTap: () => onSelected(category),
                child: ExcludeSemantics(
                  child: GestureDetector(
                    key: ValueKey('chat-history-category-${category.name}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelected(category),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: ChatHistorySearchTokens.shortcutSize,
                          height: ChatHistorySearchTokens.shortcutSize,
                          decoration: BoxDecoration(
                            color: AppTokens.accent.withValues(
                              alpha: ChatHistorySearchTokens
                                  .shortcutBackgroundOpacity,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            icon,
                            color: AppTokens.accent,
                            size: ChatHistorySearchTokens.shortcutIconSize,
                          ),
                        ),
                        const SizedBox(
                            height: ChatHistorySearchTokens.shortcutLabelGap),
                        Text(
                          label,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize:
                                ChatHistorySearchTokens.shortcutLabelFontSize,
                            color: primaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
