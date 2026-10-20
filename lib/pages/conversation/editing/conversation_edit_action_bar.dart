import 'package:openim_common/localization.dart';
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
    this.readProgress = '',
  });

  final bool hasSelection;
  final bool busy;
  final VoidCallback onMarkRead;
  final VoidCallback onArchive;
  final VoidCallback onDelete;
  final bool unarchive;
  final String readProgress;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return Material(
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
        child: SafeArea(
          top: false,
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
                    label: readProgress.isNotEmpty
                        ? readProgress
                        : chinese
                            ? (hasSelection
                                ? AppCopy.text('标记已读')
                                : AppCopy.text('全部已读'))
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
                        ? (chinese ? AppCopy.text('取消归档') : 'Unarchive')
                        : (chinese ? AppCopy.text('归档') : 'Archive'),
                  ),
                ),
                Expanded(
                  child: _action(
                    context: context,
                    key: const ValueKey('conversation-edit-delete'),
                    dark: dark,
                    onPressed: busy || !hasSelection ? null : onDelete,
                    label: chinese ? AppCopy.text('删除') : 'Delete',
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
