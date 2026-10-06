import 'package:flutter/material.dart';

import '../../services/moments_repository.dart';
import '../mine/settings/widgets/settings_widgets.dart';
import 'moments_draft_store.dart';
import 'moments_visibility_page.dart';
import 'moments_widgets.dart';

void showMomentsFeedback(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> deleteMoment(
    BuildContext context, MomentsRepository repository, MomentPost post) async {
  final scope = repository.sessionScope;
  if (!post.canDelete) return;
  final confirmed = await showSettingsConfirm(context,
      title: momentsText(context, zh: '删除动态', en: 'Delete post'),
      message: momentsText(context,
          zh: '删除后无法恢复，确认删除这条动态？',
          en: 'This post will be permanently deleted. Continue?'),
      confirmText: momentsText(context, zh: '删除', en: 'Delete'),
      destructive: true);
  if (!confirmed || !context.mounted || !repository.isSessionCurrent(scope)) {
    return;
  }
  try {
    await repository.deletePost(post.momentId);
  } catch (error) {
    if (context.mounted) {
      showMomentsFeedback(context, momentsErrorText(context, error));
    }
  }
}

Future<void> changeMomentVisibility(
    BuildContext context, MomentsRepository repository, MomentPost post) async {
  final scope = repository.sessionScope;
  if (!post.canEditVisibility) return;
  final selection =
      await Navigator.of(context).push<MomentsVisibilitySelection>(
    MaterialPageRoute(
        builder: (_) => MomentsVisibilityPage(
            repository: repository,
            initialSelection: MomentsVisibilitySelection(
                mode: post.visibility, audienceUserIds: post.audienceUserIds))),
  );
  if (selection == null ||
      !context.mounted ||
      !repository.isSessionCurrent(scope)) {
    return;
  }
  try {
    await repository.updateVisibility(post.momentId,
        visibility: selection.mode,
        audienceUserIds: selection.audienceUserIds,
        expectedVersion: post.version);
    if (context.mounted) {
      showMomentsFeedback(context,
          momentsText(context, zh: '可见范围已更新', en: 'Visibility updated'));
    }
  } catch (error) {
    if (context.mounted) {
      showMomentsFeedback(context, momentsErrorText(context, error));
    }
  }
}

Future<void> reportMoment(
    BuildContext context, MomentsRepository repository, String momentId,
    {String? commentId}) async {
  final scope = repository.sessionScope;
  if (repository.capabilities?.reportsEnabled != true) return;
  final reasons = <String, String>{
    'SPAM': momentsText(context, zh: '垃圾广告', en: 'Spam'),
    'HARASSMENT': momentsText(context, zh: '骚扰或辱骂', en: 'Harassment'),
    'INAPPROPRIATE':
        momentsText(context, zh: '不适宜内容', en: 'Inappropriate content'),
    'OTHER': momentsText(context, zh: '其他问题', en: 'Other'),
  };
  final reason = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Text(momentsText(context, zh: '举报原因', en: 'Report reason'),
                  style: Theme.of(context).textTheme.titleMedium)),
          for (final entry in reasons.entries)
            ListTile(
                title: Text(entry.value),
                onTap: () => Navigator.of(sheetContext).pop(entry.key)),
        ])),
  );
  if (reason == null ||
      !context.mounted ||
      !repository.isSessionCurrent(scope)) {
    return;
  }
  try {
    await repository.reportPost(momentId, reason: reason, commentId: commentId);
    if (context.mounted) {
      showMomentsFeedback(
          context, momentsText(context, zh: '举报已提交', en: 'Report submitted'));
    }
  } catch (error) {
    if (context.mounted) {
      showMomentsFeedback(context, momentsErrorText(context, error));
    }
  }
}

Future<void> showMomentCommentActions(
    BuildContext context,
    MomentsRepository repository,
    MomentPost post,
    MomentComment comment) async {
  final scope = repository.sessionScope;
  // The latest friendship projection is checked before opening a cached row.
  if (!repository.commentVisible(comment)) return;
  final canReply = post.canComment && !comment.replyTargetDeleted;
  final canReport = repository.capabilities?.reportsEnabled == true;
  if (!canReply && !comment.canDelete && !canReport) return;
  final action = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (canReply)
            ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(momentsText(context, zh: '回复', en: 'Reply')),
                onTap: () => Navigator.of(sheetContext).pop('reply')),
          if (comment.canDelete)
            ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(
                    momentsText(context, zh: '删除评论', en: 'Delete comment')),
                onTap: () => Navigator.of(sheetContext).pop('delete')),
          if (canReport)
            ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(momentsText(context, zh: '举报', en: 'Report')),
                onTap: () => Navigator.of(sheetContext).pop('report')),
        ])),
  );
  if (!context.mounted ||
      !repository.isSessionCurrent(scope) ||
      !repository.commentVisible(comment)) {
    return;
  }
  if (action == 'reply') {
    await showMomentsCommentSheet(context, repository, post, replyTo: comment);
  } else if (action == 'delete') {
    final confirmed = await showSettingsConfirm(context,
        title: momentsText(context, zh: '删除评论', en: 'Delete comment'),
        message:
            momentsText(context, zh: '确认删除这条评论？', en: 'Delete this comment?'),
        confirmText: momentsText(context, zh: '删除', en: 'Delete'),
        destructive: true);
    if (!confirmed || !context.mounted || !repository.isSessionCurrent(scope)) {
      return;
    }
    try {
      await repository.deleteComment(post.momentId, comment.commentId);
    } catch (error) {
      if (context.mounted) {
        showMomentsFeedback(context, momentsErrorText(context, error));
      }
    }
  } else if (action == 'report') {
    await reportMoment(context, repository, post.momentId,
        commentId: comment.commentId);
  }
}
