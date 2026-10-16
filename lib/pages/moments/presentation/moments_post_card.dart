import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import '../interactions/moments_post_actions.dart';
import '../media/moments_media_grid.dart';
import 'moments_engagement_panel.dart';
import 'moments_post_text.dart';
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
    final singleMedia =
        post.mediaList.length == 1 ? post.mediaList.first : null;
    final isLongImage = singleMedia != null &&
        !singleMedia.isVideo &&
        (singleMedia.width ?? 0) > 0 &&
        (singleMedia.height ?? 0) / singleMedia.width! >= 2;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!detail)
          Semantics(
            button: true,
            child: InkWell(
              onTap: onAuthor,
              child: Text(post.author.displayName,
                  style: TextStyle(
                      color: MomentsTheme.name(dark),
                      fontSize: MomentsLayout.nameSize,
                      fontWeight: FontWeight.w700)),
            ),
          ),
        if (post.text.trim().isNotEmpty) ...[
          if (!detail) const SizedBox(height: MomentsLayout.feedMediaRadius),
          MomentsPostText(
            key: ValueKey('moments_text_${post.momentId}'),
            text: post.text,
            detail: detail,
            onOpen: onOpen,
          ),
        ],
        if (post.mediaList.isNotEmpty) ...[
          if (post.text.trim().isNotEmpty || !detail)
            SizedBox(height: detail ? 8 : 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(detail
                ? MomentsLayout.mediaRadius
                : MomentsLayout.feedMediaRadius),
            child: ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: !detail && post.mediaList.length == 1
                        ? (isLongImage
                            ? MomentsLayout.feedLongImageWidth
                            : MomentsLayout.feedSingleMediaWidth)
                        : double.infinity),
                child: MomentsMediaGrid(
                    repository: repository,
                    post: post,
                    detail: detail,
                    onOpen: onMedia)),
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
        if (!detail)
          Row(children: [
            Expanded(
                child: Text(momentsTime(context, post.createdAt),
                    style: TextStyle(
                        color: MomentsTheme.secondary(dark),
                        fontSize: MomentsLayout.timeSize))),
            _menu(context),
          ]),
        if (detail)
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
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: MomentsLayout.feedPadding,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            button: true,
            label: post.author.displayName,
            child: InkWell(
              onTap: onAuthor,
              child: SizedBox.square(
                dimension: MomentsLayout.touchTarget,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ExcludeSemantics(
                      child: ClipRRect(
                    borderRadius:
                        BorderRadius.circular(MomentsLayout.feedMediaRadius),
                    child: AvatarView(
                        width: MomentsLayout.avatarSize,
                        height: MomentsLayout.avatarSize,
                        isCircle: false,
                        url: post.author.avatarUrl,
                        text: post.author.displayName),
                  )),
                ),
              ),
            ),
          ),
          const SizedBox(width: MomentsLayout.feedColumnGap),
          Expanded(child: content),
        ]),
      ),
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
        if (action == 'like') onLike();
        if (action == 'comment') onComment();
        if (action == 'likes') onLikes?.call();
        if (action == 'open') onOpen();
        if (action == 'delete') onDelete?.call();
        if (action == 'visibility') onVisibility?.call();
        if (action == 'report') onReport?.call();
      },
      itemBuilder: (_) => [
        if (!detail) ...[
          PopupMenuItem(
              value: 'like',
              enabled: !busy && post.canLike,
              child: Text(momentsText(context,
                  zh: post.likedByMe ? '取消点赞' : '赞',
                  en: post.likedByMe ? 'Unlike' : 'Like'))),
          PopupMenuItem(
              value: 'comment',
              enabled: !busy && post.canComment,
              child: Text(momentsText(context, zh: '评论', en: 'Comment'))),
          if (onLikes != null)
            PopupMenuItem(
                value: 'likes',
                child:
                    Text(momentsText(context, zh: '查看点赞', en: 'View likes'))),
        ],
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
