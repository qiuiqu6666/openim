import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import 'moments_comment_text.dart';
import 'moments_text.dart';
import 'moments_theme.dart';

class MomentsEngagementPanel extends StatelessWidget {
  const MomentsEngagementPanel({
    super.key,
    required this.post,
    required this.onCommentAction,
    this.onLikes,
    this.detail = false,
    this.connectedComments = false,
  });

  final MomentPost post;
  final ValueChanged<MomentComment> onCommentAction;
  final VoidCallback? onLikes;
  final bool detail, connectedComments;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final likes = post.likesPreview.take(8).toList();
    final comments = detail
        ? const <MomentComment>[]
        : post.commentsPreview.take(2).toList();
    if (likes.isEmpty && comments.isEmpty) return const SizedBox.shrink();
    return Material(
        color: MomentsTheme.panel(dark),
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(detail ? 7 : 6),
            bottom: Radius.circular(connectedComments
                ? 0
                : detail
                    ? 7
                    : 6)),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Padding(
            padding: detail
                ? const EdgeInsets.fromLTRB(0, 6, 12, 6)
                : const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (likes.isNotEmpty)
                InkWell(
                  onTap: onLikes,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                            width: detail ? 44 : 15,
                            child: Icon(
                                detail
                                    ? Icons.favorite_border_rounded
                                    : Icons.favorite_rounded,
                                color: detail
                                    ? MomentsTheme.name(dark)
                                    : MomentsTheme.notificationBadge,
                                size: detail ? 20 : 15)),
                        SizedBox(width: detail ? 10 : 6),
                        Expanded(
                          child: Wrap(
                              spacing: detail ? 5 : 4,
                              runSpacing: detail ? 5 : 4,
                              children: [
                                for (final like in likes)
                                  Tooltip(
                                    message: like.user.displayName,
                                    child: Semantics(
                                      label: like.user.displayName,
                                      image: true,
                                      child: AvatarView(
                                          text: like.user.displayName,
                                          url: like.user.avatarUrl,
                                          isCircle: true,
                                          width: detail ? 32 : 24,
                                          height: detail ? 32 : 24),
                                    ),
                                  ),
                              ]),
                        ),
                      ]),
                ),
              if (likes.isNotEmpty && comments.isNotEmpty) ...[
                const SizedBox(height: 6),
                Divider(
                    height: .6,
                    thickness: .6,
                    color: MomentsTheme.border(dark)),
                const SizedBox(height: 6),
              ],
              for (final comment in comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: InkWell(
                    onTap: () => onCommentAction(comment),
                    onLongPress: () => onCommentAction(comment),
                    child: MomentsCommentText(comment: comment, maxLines: 2),
                  ),
                ),
            ]),
          ),
          if (detail && connectedComments)
            Divider(height: 1, indent: 64, color: MomentsTheme.border(dark)),
        ]));
  }
}
