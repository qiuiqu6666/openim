import 'dart:io';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../moments_draft_store.dart';
import '../moments_widgets.dart';
import 'moments_secondary_layout.dart';

/// Attachment presentation; the page and draft store own every mutation.
class MomentsComposerMediaTile extends StatelessWidget {
  const MomentsComposerMediaTile({
    super.key,
    required this.media,
    required this.index,
    required this.imageCount,
    required this.editable,
    required this.frozen,
    required this.onPreview,
    required this.onAction,
    required this.onMove,
  });

  final MomentsDraftMedia media;
  final int index;
  final int imageCount;
  final bool editable;
  final bool frozen;
  final VoidCallback onPreview;
  final ValueChanged<String> onAction;
  final ValueChanged<String> onMove;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    final image = ClipRRect(
        borderRadius: BorderRadius.circular(MomentsSecondaryLayout.imageRadius),
        child: Image.file(File(media.path),
            fit: BoxFit.cover,
            cacheWidth: 480,
            errorBuilder: (_, __, ___) => ColoredBox(
                color: AppTokens.surfaceAlt(dark: dark),
                child: Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: AppTokens.textSecondary(dark: dark))))));
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          editable && details.data != media.clientMediaId,
      onAcceptWithDetails: (details) => onMove(details.data),
      builder: (_, candidates, __) => LongPressDraggable<String>(
        data: media.clientMediaId,
        maxSimultaneousDrags: editable ? 1 : 0,
        feedback: SizedBox(
            width: AppTokens.s8 * 3, height: AppTokens.s8 * 3, child: image),
        child: Semantics(
          label: momentsText(context,
              zh: '图片 ${index + 1}', en: 'Image ${index + 1}'),
          child: DecoratedBox(
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTokens.rMd),
                  border: candidates.isNotEmpty
                      ? Border.all(color: AppTokens.accent, width: AppTokens.s2)
                      : null),
              child: Stack(fit: StackFit.expand, children: [
                InkWell(
                    borderRadius: BorderRadius.circular(
                        MomentsSecondaryLayout.imageRadius),
                    onTap: onPreview,
                    child: image),
                if (editable)
                  Positioned(
                      top: -6,
                      left: -6,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(AppTokens.rPill),
                        child: PopupMenuButton<String>(
                            key: ValueKey('moments_image_menu_$index'),
                            tooltip: momentsText(context,
                                zh: '图片选项', en: 'Image options'),
                            onSelected: onAction,
                            itemBuilder: (_) => [
                                  if (index > 0)
                                    PopupMenuItem(
                                        value: 'earlier',
                                        child: Text(momentsText(context,
                                            zh: '向前移动', en: 'Move earlier'))),
                                  if (index < imageCount - 1)
                                    PopupMenuItem(
                                        value: 'later',
                                        child: Text(momentsText(context,
                                            zh: '向后移动', en: 'Move later'))),
                                  PopupMenuItem(
                                      value: 'remove',
                                      child: Text(momentsText(context,
                                          zh: '删除图片', en: 'Remove image'))),
                                ],
                            child: const _MediaActionBadge(
                                icon: Icons.more_horiz_rounded)),
                      )),
                if (editable)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Tooltip(
                      message:
                          momentsText(context, zh: '删除图片', en: 'Remove image'),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: ValueKey('moments_image_remove_$index'),
                          onTap: () => onAction('remove'),
                          customBorder: const CircleBorder(),
                          child: const _MediaActionBadge(
                              icon: Icons.close_rounded),
                        ),
                      ),
                    ),
                  ),
                if (frozen)
                  Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                          value: media.mediaId != null ? 1 : media.progress,
                          color: AppTokens.accent,
                          backgroundColor: AppTokens.surfaceAlt(dark: dark))),
              ])),
        ),
      ),
    );
  }
}

class _MediaActionBadge extends StatelessWidget {
  const _MediaActionBadge({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: MomentsLayout.touchTarget,
        child: Center(
          child: Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(
                color: MomentsTheme.mediaBadge, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: MomentsTheme.coverForeground),
          ),
        ),
      );
}
