import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import '../presentation/moments_text.dart';
import '../presentation/moments_theme.dart';

/// The existing like/comment controls are the user's visual exception.
class MomentsPostActions extends StatelessWidget {
  const MomentsPostActions({
    super.key,
    required this.post,
    required this.onLike,
    required this.onComment,
    this.onLikes,
    this.busy = false,
  });

  final MomentPost post;
  final VoidCallback onLike, onComment;
  final VoidCallback? onLikes;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final secondary = AppTokens.textSecondary(dark: momentsDark(context));
    return Wrap(
        spacing: AppTokens.s5,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _action(context,
              key: ValueKey('moments_like_${post.momentId}'),
              icon: post.likedByMe
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: post.interactionCountsTrusted && post.likeCount > 0
                  ? '${post.likeCount}'
                  : momentsText(context, zh: '赞', en: 'Like'),
              color: post.likedByMe ? AppTokens.accent : secondary,
              onTap: busy || !post.canLike ? null : onLike),
          _action(context,
              key: ValueKey('moments_comment_${post.momentId}'),
              icon: Icons.chat_bubble_outline_rounded,
              label: post.interactionCountsTrusted && post.commentCount > 0
                  ? '${post.commentCount}'
                  : momentsText(context, zh: '评论', en: 'Comment'),
              color: secondary,
              onTap: busy || !post.canComment ? null : onComment),
          if (onLikes != null &&
              (post.likesPreview.isNotEmpty ||
                  post.interactionCountsTrusted && post.likeCount > 0))
            TextButton(
                onPressed: onLikes,
                child: Text(momentsText(context, zh: '查看点赞', en: 'View likes'),
                    style:
                        const TextStyle(fontSize: MomentsLayout.captionSize))),
          if (busy)
            const SizedBox.square(
                dimension: AppTokens.s5,
                child: CircularProgressIndicator(strokeWidth: 2)),
        ]);
  }

  Widget _action(BuildContext context,
          {required Key key,
          required IconData icon,
          required String label,
          required Color color,
          required VoidCallback? onTap}) =>
      TextButton.icon(
        key: key,
        onPressed: onTap,
        icon: Icon(icon, size: AppTokens.s6, color: color),
        label: Text(label,
            style:
                TextStyle(color: color, fontSize: MomentsLayout.captionSize)),
        style: TextButton.styleFrom(
            minimumSize: const Size(
                MomentsLayout.touchTarget, MomentsLayout.touchTarget),
            padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2)),
      );
}
