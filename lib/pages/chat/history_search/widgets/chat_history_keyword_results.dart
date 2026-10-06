import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../chat_history_category.dart';
import '../chat_history_search_controller.dart';
import '../chat_history_search_strings.dart';
import '../chat_history_search_tokens.dart';
import 'chat_history_result_tile.dart';
import 'chat_history_search_shortcuts.dart';
import 'chat_history_search_layout.dart';

/// The shortcut hub stays in the same scroll surface as keyword results.
class ChatHistoryKeywordResults extends StatelessWidget {
  const ChatHistoryKeywordResults({
    super.key,
    required this.controller,
    required this.isGroup,
    required this.waiting,
    required this.onCategory,
    required this.onMessage,
    required this.onRefresh,
  });

  final ChatHistorySearchController controller;
  final bool isGroup;
  final bool waiting;
  final ValueChanged<ChatHistoryCategory> onCategory;
  final ValueChanged<Message> onMessage;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final avatarSize = chatHistorySearchIsDesktop(context)
        ? ChatHistorySearchTokens.desktopAvatarSize
        : ChatHistorySearchTokens.avatarSize;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: RefreshIndicator(
        color: AppTokens.accent,
        backgroundColor: ChatHistorySearchTokens.pageBackground(dark: dark),
        onRefresh: onRefresh,
        child: Scrollbar(
          child: ListView.separated(
            key: const PageStorageKey('chat-history-results-list'),
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: controller.results.length + 2,
            separatorBuilder: (_, index) =>
                index > 0 && index <= controller.results.length
                    ? Divider(
                        height: ChatHistorySearchTokens.dividerThickness,
                        thickness: ChatHistorySearchTokens.dividerThickness,
                        indent: ChatHistorySearchTokens.horizontalPadding +
                            avatarSize +
                            ChatHistorySearchTokens.avatarTextGap,
                        endIndent: ChatHistorySearchTokens.horizontalPadding,
                        color: ChatHistorySearchTokens.divider(dark: dark),
                      )
                    : const SizedBox.shrink(),
            itemBuilder: (context, index) {
              if (index == 0) {
                return ChatHistorySearchShortcuts(
                    isGroup: isGroup, onSelected: onCategory);
              }
              if (index == controller.results.length + 1) {
                return _status(context);
              }
              final message = controller.results[index - 1];
              return Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: ChatHistorySearchTokens.horizontalPadding),
                child: ChatHistoryResultTile(
                  key: ValueKey('chat-history-result-${message.clientMsgID}'),
                  message: message,
                  onTap: () => onMessage(message),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _status(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = AppTokens.textSecondary(dark: dark);
    if (waiting || controller.loading) {
      return const Center(
        child: SizedBox.square(
          dimension: ChatHistorySearchTokens.loaderSize,
          child: CircularProgressIndicator(
            strokeWidth: ChatHistorySearchTokens.loaderStrokeWidth,
            color: AppTokens.accent,
          ),
        ),
      );
    }
    if (controller.failed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTokens.s7),
        child: Column(children: [
          Text(chatHistorySearchText(context, 'failed'),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
          TextButton(
            key: const ValueKey('chat-history-retry'),
            style: TextButton.styleFrom(foregroundColor: AppTokens.accent),
            onPressed: controller.retry,
            child: Text(chatHistorySearchText(context, 'retry')),
          ),
        ]),
      );
    }
    if (controller.hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: ChatHistorySearchTokens.horizontalPadding),
        child: Material(
          color: AppTokens.surface(dark: dark),
          child: InkWell(
            key: const ValueKey('chat-history-more'),
            onTap: controller.loadMore,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.s3),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppTokens.border(dark: dark),
                    width: ChatHistorySearchTokens.moreDividerThickness,
                  ),
                ),
              ),
              child: Row(children: [
                Icon(Icons.search, color: muted),
                const SizedBox(width: AppTokens.s4),
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(
                      vertical: ChatHistoryFileTokens.rowVerticalPadding),
                  child: Text(chatHistorySearchText(context, 'moreMessages'),
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: chatHistorySearchIsDesktop(context)
                              ? ChatHistorySearchTokens.shortcutLabelFontSize
                              : ChatHistorySearchTokens.titleFontSize,
                          fontWeight: FontWeight.w400,
                          color: AppTokens.textPrimary(dark: dark))),
                )),
                Icon(Icons.expand_more, color: muted),
              ]),
            ),
          ),
        ),
      );
    }
    if (controller.hasSearched && controller.results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: ChatHistorySearchTokens.emptyHorizontalPadding,
          vertical: ChatHistorySearchTokens.emptyVerticalPadding,
        ),
        child: Column(children: [
          Image.asset('assets/img/empty.webp',
              width: ChatHistorySearchTokens.emptyImageWidth,
              errorBuilder: (_, __, ___) => Icon(Icons.inbox_outlined,
                  color: muted, size: ChatHistorySearchTokens.shortcutSize)),
          const SizedBox(height: AppTokens.s5),
          Text(chatHistorySearchText(context, 'empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: ChatHistorySearchTokens.searchFontSize,
                height: ChatHistorySearchTokens.emptyTextHeight,
                color: muted,
              )),
        ]),
      );
    }
    return const SizedBox.shrink();
  }
}
