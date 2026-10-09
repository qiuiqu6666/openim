import 'package:flutter/material.dart';

import '../../../services/moments_repository.dart';
import '../presentation/moments_text.dart';
import '../presentation/moments_theme.dart';
import 'moments_media_image.dart';
import 'moments_single_media_frame.dart';

class MomentsMediaGrid extends StatelessWidget {
  const MomentsMediaGrid({
    super.key,
    required this.repository,
    required this.post,
    required this.onOpen,
    this.detail = false,
  });

  final MomentsRepository repository;
  final MomentPost post;
  final ValueChanged<int> onOpen;
  final bool detail;

  @override
  Widget build(BuildContext context) {
    final media = post.mediaList;
    if (media.isEmpty) return const SizedBox.shrink();
    Widget tile(int index, {ValueChanged<Size>? onDimensions}) {
      final item = media[index];
      final radius = BorderRadius.circular(detail && media.length == 1
          ? 12
          : detail
              ? 10
              : 6);
      final longImage =
          (item.width ?? 0) > 0 && (item.height ?? 0) / item.width! >= 2;
      return Semantics(
        button: true,
        label: momentsText(context,
            zh: item.isVideo ? '查看视频' : '查看第${index + 1}张图片',
            en: item.isVideo ? 'View video' : 'View image ${index + 1}'),
        child: InkWell(
          key: ValueKey('moments_media_${post.momentId}_$index'),
          onTap: () => onOpen(index),
          borderRadius: radius,
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(fit: StackFit.expand, children: [
              MomentsMediaImage(
                key: ValueKey('${repository.currentUserId}:${item.mediaId}'),
                repository: repository,
                media: item,
                onDimensions: onDimensions,
              ),
              if (item.isVideo)
                const Center(
                    child: Icon(Icons.play_circle_fill_rounded,
                        color: MomentsTheme.coverForeground, size: 48)),
              if (longImage && !item.isVideo)
                Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                            color: MomentsTheme.mediaBadge,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(momentsText(context, zh: '长图', en: 'Long'),
                            style: const TextStyle(
                                color: MomentsTheme.coverForeground,
                                fontSize: 10)))),
            ]),
          ),
        ),
      );
    }

    if (media.length == 1) {
      return MomentsSingleMediaFrame(
          media: media.first,
          maxLongImageHeight: detail ? 520 : 420,
          imageBuilder: (callback) => tile(0, onDimensions: callback));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: media.length.clamp(0, 9),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: detail ? 6 : MomentsLayout.mediaGap,
          mainAxisSpacing: detail ? 6 : MomentsLayout.mediaGap),
      itemBuilder: (_, index) => tile(index),
    );
  }
}
