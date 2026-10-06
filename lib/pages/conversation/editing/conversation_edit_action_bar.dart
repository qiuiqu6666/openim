// Adapted from 99chat's conversation.dart editing action bar.
// Source: https://github.com/qiuiqu6666/99chat (Apache License 2.0).
// Changes: use AppTokens and caller-provided OpenIM action callbacks.
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import 'conversation_edit_tokens.dart';

class ConversationEditActionBar extends StatelessWidget {
  const ConversationEditActionBar({
    super.key,
    required this.hasSelection,
    required this.busy,
    required this.onMarkRead,
    required this.onArchive,
    required this.onDelete,
    this.unarchive = false,
  });

  final bool hasSelection;
  final bool busy;
  final VoidCallback onMarkRead;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final bool unarchive;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return SafeArea(
      top: false,
      child: Material(
        color: ConversationEditTokens.actionBarBackground(dark: dark),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: ConversationEditTokens.divider(dark: dark),
                width: ConversationEditTokens.dividerWidth,
              ),
            ),
          ),
          child: SizedBox(
            height: ConversationEditTokens.actionBarHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _action(
                    context: context,
                    key: const ValueKey('conversation-edit-mark-read'),
                    dark: dark,
                    onPressed: busy ? null : onMarkRead,
                    label: chinese
                        ? (hasSelection ? '标记已读' : '全部已读')
                        : (hasSelection ? 'Mark as read' : 'Read all'),
                  ),
                ),
                Expanded(
                  child: _action(
                    context: context,
                    key: const ValueKey('conversation-edit-archive'),
                    dark: dark,
                    onPressed: busy || !hasSelection ? null : onArchive,
                    label: unarchive
                        ? (chinese ? '取消归档' : 'Unarchive')
                        : (chinese ? '归档' : 'Archive'),
                  ),
                ),
                Expanded(
                  child: _action(
                    context: context,
                    key: const ValueKey('conversation-edit-delete'),
                    dark: dark,
                    onPressed: busy || !hasSelection ? null : onDelete,
                    label: chinese ? '删除' : 'Delete',
                    color: ConversationEditTokens.delete,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _action({
    required BuildContext context,
    required Key key,
    required bool dark,
    required VoidCallback? onPressed,
    required String label,
    Color color = AppTokens.accent,
  }) =>
      TextButton(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          disabledForegroundColor: AppTokens.textPrimary(dark: dark)
              .withValues(alpha: ConversationEditTokens.disabledOpacity),
          textStyle: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(fontSize: AppTokens.captionFontSize),
        ),
        child: Text(label,
            style: color == ConversationEditTokens.delete
                ? TextStyle(color: color)
                : null),
      );
}
