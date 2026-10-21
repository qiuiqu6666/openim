import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../../../../services/moments_repository.dart';
import '../../moments_widgets.dart';
import '../../presentation/moments_secondary_layout.dart';

class MomentsNotificationRow extends StatelessWidget {
  const MomentsNotificationRow({
    super.key,
    required this.repository,
    required this.item,
    required this.text,
    required this.onTap,
    required this.showDivider,
  });

  final MomentsRepository repository;
  final MomentNotification item;
  final String text;
  final VoidCallback onTap;
  final bool showDivider;

  Widget _message(BuildContext context, bool dark, String comment) {
    final style = TextStyle(
        color: MomentsTheme.text(dark),
        fontSize: MomentsSecondaryLayout.messageSize,
        height: 1.25);
    final target = item.replyToUser;
    if (item.type.toUpperCase().contains('REPLY') && target != null) {
      return Text.rich(
          TextSpan(style: style, children: [
            TextSpan(text: momentsText(context, zh: '回复了 ', en: 'Replied to ')),
            TextSpan(
                text: item.comment?.replyTargetDeleted == true
                    ? momentsText(context, zh: '已删除评论', en: 'Deleted comment')
                    : target.displayName,
                style: TextStyle(
                    color: MomentsTheme.name(dark),
                    fontWeight: FontWeight.w600)),
            if (comment.isNotEmpty) TextSpan(text: '：$comment'),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis);
    }
    return Text(comment.isEmpty ? text : comment,
        maxLines: 2, overflow: TextOverflow.ellipsis, style: style);
  }

  Widget _preview(BuildContext context, bool dark) {
    final media = item.previewMedia;
    final text = item.momentText.trim();
    final label = media == null
        ? (text.isEmpty ? momentsText(context, zh: '动态', en: 'Moment') : text)
        : momentsText(context,
            zh: media.isVideo ? '视频' : '图片',
            en: media.isVideo ? 'Video' : 'Photo');
    return Semantics(
      label: media == null ? null : label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
            MomentsSecondaryLayout.notificationPreviewRadius),
        child: SizedBox.square(
          dimension: MomentsSecondaryLayout.notificationPreview,
          child: ColoredBox(
            color: MomentsTheme.panel(dark),
            child: media == null
                ? Padding(
                    padding: const EdgeInsets.all(
                        MomentsSecondaryLayout.notificationPreviewRadius),
                    child: Text(label,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: MomentsTheme.secondary(dark),
                            fontSize: MomentsSecondaryLayout.draftSize,
                            height: 1.2)))
                : Stack(fit: StackFit.expand, children: [
                    if (!media.isVideo ||
                        media.thumbPath.isNotEmpty ||
                        media.mediaId.isNotEmpty)
                      MomentsMediaImage(
                          repository: repository,
                          media: media.isVideo && media.thumbPath.isEmpty
                              ? MomentMedia(
                                  mediaId: media.mediaId,
                                  type: media.type,
                                  thumbPath:
                                      '/moments/media/${Uri.encodeComponent(media.mediaId)}/content?variant=thumb')
                              : media),
                    if (media.isVideo)
                      Center(
                          child: Icon(Icons.play_circle_outline,
                              color: Theme.of(context).colorScheme.onPrimary,
                              size: MomentsSecondaryLayout.notificationAvatar)),
                  ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    if (!item.available) {
      return Padding(
          padding: MomentsSecondaryLayout.notificationInset,
          child: Text(
              momentsText(context,
                  zh: '内容已不可用', en: 'Content is no longer available'),
              style: TextStyle(color: MomentsTheme.secondary(dark))));
    }
    final local = item.createdAt > 0
        ? DateTime.fromMillisecondsSinceEpoch(item.createdAt).toLocal()
        : null;
    final timestamp = local == null
        ? null
        : momentsText(context,
            zh: '${local.month}月${local.day}日 ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
            en: '${MaterialLocalizations.of(context).formatShortDate(local)} ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(local))}');
    final liked = item.type.toUpperCase().contains('LIKE');
    final comment = item.comment?.text.trim() ?? '';
    return Column(children: [
      Semantics(
          button: true,
          child: Material(
              color: Colors.transparent,
              child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: MomentsSecondaryLayout.notificationInset,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AvatarView(
                              width: MomentsSecondaryLayout.notificationAvatar,
                              height: MomentsSecondaryLayout.notificationAvatar,
                              url: item.actor.avatarUrl,
                              text: item.actor.displayName),
                          const SizedBox(
                              width: MomentsSecondaryLayout.avatarGap),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(item.actor.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: MomentsTheme.name(dark),
                                        fontSize:
                                            MomentsSecondaryLayout.nameSize,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                liked
                                    ? Semantics(
                                        label: text,
                                        child: Icon(
                                            Icons.favorite_border_rounded,
                                            color: MomentsTheme.name(dark),
                                            size: 24))
                                    : _message(context, dark, comment),
                                if (timestamp != null) ...[
                                  const SizedBox(height: 5),
                                  Text(timestamp,
                                      style: TextStyle(
                                          color: MomentsTheme.secondary(dark),
                                          fontSize: MomentsSecondaryLayout
                                              .captionSize)),
                                ],
                              ])),
                          const SizedBox(
                              width: MomentsSecondaryLayout.avatarGap),
                          _preview(context, dark),
                        ]),
                  )))),
      if (showDivider)
        Divider(
            height: 1,
            thickness: MomentsSecondaryLayout.notificationDividerWidth,
            indent: MomentsSecondaryLayout.notificationDividerIndent,
            color: MomentsTheme.border(dark)),
    ]);
  }
}
