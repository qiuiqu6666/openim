import 'package:flutter/material.dart';

import '../../../services/moments_repository.dart';
import '../interactions/moments_post_actions.dart';
import '../media/moments_media_image.dart';
import 'moments_text.dart';
import 'moments_theme.dart';

class MomentsProfileTimelineItem extends StatelessWidget {
  const MomentsProfileTimelineItem({
    super.key,
    required this.repository,
    required this.post,
    required this.showDate,
    required this.onOpen,
    required this.onMedia,
    required this.onLike,
    required this.onComment,
    this.onLikes,
    this.busy = false,
  });

  final MomentsRepository repository;
  final MomentPost post;
  final bool showDate, busy;
  final VoidCallback onOpen, onLike, onComment;
  final VoidCallback? onLikes;
  final ValueChanged<int> onMedia;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final date = DateTime.fromMillisecondsSinceEpoch(post.createdAt);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: MomentsLayout.timelinePadding,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: MomentsLayout.timelineDateWidth,
              child: showDate
                  ? MomentsTimelineDate(
                      key: ValueKey(
                          'moments_album_day_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}'),
                      date: date)
                  : null,
            ),
            const SizedBox(width: MomentsLayout.timelineGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (post.mediaList.isNotEmpty) ...[
                      MomentsTimelineCollage(
                          repository: repository, post: post, onOpen: onMedia),
                      const SizedBox(width: MomentsLayout.timelineGap),
                    ],
                    Expanded(
                      child: Text(
                        post.text.trim().isNotEmpty
                            ? post.text.trim()
                            : post.mediaList.isNotEmpty
                                ? momentsText(context,
                                    zh: '分享图片', en: 'Shared images')
                                : momentsText(context,
                                    zh: '这一刻', en: 'This moment'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: post.text.trim().isEmpty
                                ? MomentsTheme.secondary(dark)
                                : MomentsTheme.text(dark),
                            fontSize: post.text.trim().isEmpty ? 15 : 16,
                            height: 1.35),
                      ),
                    ),
                  ]),
                  // Preserve the user's existing controls in the album too.
                  const SizedBox(height: 6),
                  MomentsPostActions(
                      post: post,
                      busy: busy,
                      onLike: onLike,
                      onComment: onComment,
                      onLikes: onLikes),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class MomentsTimelineDate extends StatelessWidget {
  const MomentsTimelineDate({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final local = date.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == today || day == yesterday) {
      return Text(
          day == today
              ? momentsText(context, zh: '今天', en: 'Today')
              : momentsText(context, zh: '昨天', en: 'Yesterday'),
          textAlign: TextAlign.right,
          maxLines: 2,
          style: TextStyle(
              color: MomentsTheme.text(dark),
              fontSize: 28,
              height: 1,
              fontWeight: FontWeight.w700));
    }
    final month = local.year == now.year
        ? momentsText(context, zh: '${local.month}月', en: '${local.month}')
        : '${local.year}.${local.month}';
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topRight,
      child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(local.day.toString().padLeft(2, '0'),
                style: TextStyle(
                    color: MomentsTheme.text(dark),
                    fontSize: 26,
                    height: 1,
                    fontWeight: FontWeight.w600)),
            const SizedBox(width: 2),
            Text(month,
                style: TextStyle(
                    color: MomentsTheme.secondary(dark), fontSize: 12)),
          ]),
    );
  }
}

class MomentsTodayComposer extends StatelessWidget {
  const MomentsTodayComposer({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                  width: MomentsLayout.timelineDateWidth,
                  child: Text(momentsText(context, zh: '今天', en: 'Today'),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: MomentsTheme.text(dark),
                          fontSize: 28,
                          height: 1,
                          fontWeight: FontWeight.w700))),
              const SizedBox(width: MomentsLayout.timelineGap),
              Container(
                  width: 104,
                  height: 104,
                  decoration: BoxDecoration(
                      color: MomentsTheme.composerTile(dark),
                      borderRadius: BorderRadius.circular(2)),
                  alignment: Alignment.center,
                  child: Icon(Icons.camera_alt_rounded,
                      size: 34, color: MomentsTheme.composerIcon(dark))),
            ]),
          ),
        ));
  }
}

class MomentsTimelineCollage extends StatelessWidget {
  const MomentsTimelineCollage(
      {super.key,
      required this.repository,
      required this.post,
      required this.onOpen});
  final MomentsRepository repository;
  final MomentPost post;
  final ValueChanged<int> onOpen;

  @override
  Widget build(BuildContext context) {
    final items = post.mediaList;
    if (items.isEmpty) return const SizedBox.shrink();
    Widget tile(int index) => InkWell(
        onTap: () => onOpen(index),
        child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: MomentsMediaImage(
                repository: repository, media: items[index])));
    Widget collage;
    if (items.length == 1) {
      collage = tile(0);
    } else if (items.length == 2 || items.length > 4) {
      collage = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: tile(0)),
        const SizedBox(width: 3),
        Expanded(
            child: items.length == 2
                ? tile(1)
                : Stack(fit: StackFit.expand, children: [
                    tile(1),
                    IgnorePointer(
                        child: DecoratedBox(
                            decoration: BoxDecoration(
                                color: MomentsTheme.collageOverlay,
                                borderRadius: BorderRadius.circular(6)),
                            child: Center(
                                child: Text('+${items.length - 2}',
                                    style: const TextStyle(
                                        color: MomentsTheme.coverForeground,
                                        fontSize: 17,
                                        fontWeight: FontWeight.w600)))))
                  ])),
      ]);
    } else if (items.length == 3) {
      collage = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(child: tile(0)),
        const SizedBox(width: 3),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Expanded(child: tile(1)),
              const SizedBox(height: 3),
              Expanded(child: tile(2))
            ])),
      ]);
    } else {
      collage = GridView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 4,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, crossAxisSpacing: 3, mainAxisSpacing: 3),
          itemBuilder: (_, index) => tile(index));
    }
    return SizedBox(
        width: MomentsLayout.timelineMediaSize,
        height: MomentsLayout.timelineMediaSize,
        child: collage);
  }
}
