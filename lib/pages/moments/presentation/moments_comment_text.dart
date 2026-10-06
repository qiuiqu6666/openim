import 'package:flutter/material.dart';
import '../../../services/moments_repository.dart';
import 'moments_text.dart';
import 'moments_theme.dart';

class MomentsCommentText extends StatelessWidget {
  const MomentsCommentText({super.key, required this.comment, this.maxLines});
  final MomentComment comment;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(
              text: comment.author.displayName,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: MomentsTheme.name(momentsDark(context)))),
          if (comment.replyToUser != null || comment.replyTargetDeleted) ...[
            TextSpan(
                text: momentsText(context, zh: ' 回复 ', en: ' replied to ')),
            TextSpan(
                text: comment.replyTargetDeleted
                    ? momentsText(context, zh: '已删除评论', en: 'Deleted comment')
                    : comment.replyToUser!.displayName,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: MomentsTheme.name(momentsDark(context)))),
          ],
          TextSpan(text: '：${comment.text}'),
        ]),
        maxLines: maxLines,
        overflow:
            maxLines == null ? TextOverflow.visible : TextOverflow.ellipsis,
        style: TextStyle(
            color: MomentsTheme.text(momentsDark(context)),
            fontSize: 13,
            height: 1.25),
      );
}
