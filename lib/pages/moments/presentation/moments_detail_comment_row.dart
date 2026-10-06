import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import 'moments_text.dart';
import 'moments_theme.dart';

/// A detail comment presentation row; permissions and actions stay in the page.
class MomentsDetailCommentRow extends StatelessWidget {
  const MomentsDetailCommentRow({
    super.key,
    required this.comment,
    required this.onAction,
    this.isFirst = false,
    this.isLast = false,
    this.startsPanel = false,
    this.onAuthor,
  });

  final MomentComment comment;
  final VoidCallback onAction;
  final bool isFirst;
  final bool isLast;
  final bool startsPanel;
  final VoidCallback? onAuthor;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final nameColor = MomentsTheme.name(dark);
    final radius = BorderRadius.vertical(
      top: startsPanel ? const Radius.circular(7) : Radius.zero,
      bottom: isLast ? const Radius.circular(7) : Radius.zero,
    );
    final hasReply = comment.replyToUser != null || comment.replyTargetDeleted;
    final targetName = comment.replyTargetDeleted
        ? momentsText(context, zh: '已删除评论', en: 'Deleted comment')
        : comment.replyToUser?.displayName ?? '';
    final bodyStyle = TextStyle(
      color: MomentsTheme.text(dark),
      fontSize: 14,
      height: 1.24,
      fontWeight: FontWeight.w500,
    );

    return ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        color: MomentsTheme.panel(dark),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              onLongPress: onAction,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 12, 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: isFirst
                          ? Icon(Icons.chat_bubble_outline,
                              color: nameColor, size: 20)
                          : null,
                    ),
                    const SizedBox(width: 10),
                    AvatarView(
                      url: comment.author.avatarUrl,
                      text: comment.author.displayName,
                      width: 32,
                      height: 32,
                      isCircle: true,
                      onTap: onAuthor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LayoutBuilder(
                              builder: (context, constraints) => Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          comment.author.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: nameColor,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth: constraints.maxWidth / 2),
                                        child: Text(
                                          momentsDetailTime(
                                              context, comment.createdAt,
                                              includeYear: false),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color:
                                                  MomentsTheme.secondary(dark),
                                              fontSize: 11),
                                        ),
                                      ),
                                    ],
                                  )),
                          const SizedBox(height: 1),
                          Text.rich(
                            TextSpan(
                              children: [
                                if (hasReply) ...[
                                  TextSpan(
                                      text: momentsText(context,
                                          zh: '回复 ', en: 'Reply to ')),
                                  TextSpan(
                                      text: targetName,
                                      style: TextStyle(
                                          color: nameColor,
                                          fontWeight: FontWeight.w600)),
                                  const TextSpan(text: '：'),
                                ],
                                TextSpan(text: comment.text),
                              ],
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: bodyStyle,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (!isLast)
              Divider(height: 1, indent: 94, color: MomentsTheme.border(dark)),
          ],
        ),
      ),
    );
  }
}
