import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import '../interactions/moments_post_actions.dart';
import '../media/moments_media_grid.dart';
import 'moments_engagement_panel.dart';
import 'moments_text.dart';
import 'moments_theme.dart';

class MomentsPostCard extends StatelessWidget {
  const MomentsPostCard({
    super.key,
    required this.repository,
    required this.post,
    required this.onOpen,
    required this.onAuthor,
    required this.onLike,
    required this.onComment,
    required this.onMedia,
    required this.onCommentAction,
    this.onDelete,
    this.onVisibility,
    this.onReport,
    this.onLikes,
    this.busy = false,
    this.detail = false,
  });

  final MomentsRepository repository;
  final MomentPost post;
  final VoidCallback onOpen, onAuthor, onLike, onComment;
  final ValueChanged<int> onMedia;
  final ValueChanged<MomentComment> onCommentAction;
  final VoidCallback? onDelete, onVisibility, onReport, onLikes;
  final bool busy, detail;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!detail)
          Row(children: [
            AvatarView(
                width: MomentsLayout.avatarSize,
                height: MomentsLayout.avatarSize,
                isCircle: true,
                url: post.author.avatarUrl,
                text: post.author.displayName,
                onTap: onAuthor),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onAuthor,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post.author.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: MomentsTheme.text(dark),
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(momentsTime(context, post.createdAt),
                          style: TextStyle(
                              color: MomentsTheme.secondary(dark),
                              fontSize: 12)),
                    ]),
              ),
            ),
            _menu(context),
          ]),
        if (post.text.trim().isNotEmpty) ...[
          if (!detail) const SizedBox(height: 10),
          InkWell(
            onTap: detail ? null : onOpen,
            child: Text(post.text,
                style: TextStyle(
                    color: MomentsTheme.text(dark),
                    fontSize: 15,
                    height: detail ? 1.45 : 1.5)),
          ),
        ],
        if (post.mediaList.isNotEmpty) ...[
          if (post.text.trim().isNotEmpty || !detail)
            SizedBox(height: detail ? 8 : 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MomentsMediaGrid(
                repository: repository,
                post: post,
                detail: detail,
                onOpen: onMedia),
          ),
        ],
        if (detail) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: Text(momentsDetailTime(context, post.createdAt),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: MomentsTheme.secondary(dark), fontSize: 13))),
            _menu(context),
          ]),
        ],
        const SizedBox(height: 6),
        MomentsPostActions(
            post: post,
            busy: busy,
            onLike: onLike,
            onComment: onComment,
            onLikes: onLikes),
        if (!detail &&
            (post.likesPreview.isNotEmpty || post.commentsPreview.isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: MomentsEngagementPanel(
                post: post, onLikes: onLikes, onCommentAction: onCommentAction),
          ),
      ],
    );
    if (detail) {
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AvatarView(
            width: MomentsLayout.detailAvatarSize,
            height: MomentsLayout.detailAvatarSize,
            isCircle: true,
            url: post.author.avatarUrl,
            text: post.author.displayName,
            onTap: onAuthor),
        const SizedBox(width: 16),
        Expanded(child: content),
      ]);
    }
    return Material(
      color: MomentsTheme.card(dark),
      borderRadius: BorderRadius.circular(MomentsLayout.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Padding(padding: MomentsLayout.cardPadding, child: content),
    );
  }

  Widget _menu(BuildContext context) {
    if (detail &&
        onDelete == null &&
        onVisibility == null &&
        onReport == null) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: momentsText(context, zh: '更多', en: 'More'),
      icon: Icon(Icons.more_horiz_rounded,
          color: MomentsTheme.secondary(momentsDark(context))),
      onSelected: (action) {
        if (action == 'open') onOpen();
        if (action == 'delete') onDelete?.call();
        if (action == 'visibility') onVisibility?.call();
        if (action == 'report') onReport?.call();
      },
      itemBuilder: (_) => [
        if (!detail)
          PopupMenuItem(
              value: 'open',
              child:
                  Text(momentsText(context, zh: '查看详情', en: 'View details'))),
        if (onVisibility != null)
          PopupMenuItem(
              value: 'visibility',
              child: Text(
                  momentsText(context, zh: '修改可见范围', en: 'Change visibility'))),
        if (onDelete != null)
          PopupMenuItem(
              value: 'delete',
              child: Text(momentsText(context, zh: '删除', en: 'Delete'))),
        if (onReport != null)
          PopupMenuItem(
              value: 'report',
              child: Text(momentsText(context, zh: '举报', en: 'Report'))),
      ],
    );
  }
}
