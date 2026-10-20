import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../moments_widgets.dart';
import 'moments_secondary_layout.dart';

/// Visual composer surface; upload, draft and publish state stay in the page.
class MomentsComposerLayout extends StatelessWidget {
  const MomentsComposerLayout({
    super.key,
    required this.name,
    required this.controller,
    required this.editable,
    required this.maxText,
    required this.visibilityLabel,
    required this.status,
    this.avatarUrl,
    this.media,
    this.onPickPhotos,
    this.onVisibility,
    this.picking = false,
  });

  final String name;
  final String? avatarUrl;
  final TextEditingController controller;
  final bool editable;
  final int maxText;
  final String visibilityLabel;
  final Widget? media;
  final Widget status;
  final VoidCallback? onPickPhotos;
  final VoidCallback? onVisibility;
  final bool picking;

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        AvatarView(
            url: avatarUrl,
            text: name,
            width: MomentsSecondaryLayout.avatarSize,
            height: MomentsSecondaryLayout.avatarSize),
        const SizedBox(width: MomentsSecondaryLayout.avatarGap),
        Expanded(
            child: Text(name,
                style: TextStyle(
                    color: MomentsTheme.text(dark),
                    fontSize: MomentsSecondaryLayout.nameSize,
                    fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: MomentsSecondaryLayout.pageInset),
      TextField(
          key: const ValueKey('moments_compose_text'),
          controller: controller,
          enabled: editable,
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: momentsText(context,
                  zh: '这一刻的想法...', en: 'What is on your mind...'),
              hintStyle: TextStyle(color: MomentsTheme.secondary(dark)),
              errorText:
                  graphemeTrim(controller.text).characters.length > maxText
                      ? momentsText(context,
                          zh: AppCopy.format('正文最多 {#0} 个字', [maxText]),
                          en: 'Use no more than $maxText characters')
                      : null),
          style: TextStyle(
              color: MomentsTheme.text(dark),
              fontSize: MomentsSecondaryLayout.nameSize,
              height: MomentsSecondaryLayout.bodyHeight)),
      const SizedBox(height: MomentsSecondaryLayout.avatarGap),
      if (media != null) ...[
        media!,
        const SizedBox(height: MomentsSecondaryLayout.avatarGap),
      ],
      Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          button: true,
          enabled: onPickPhotos != null,
          child: Material(
            color: MomentsTheme.composerTile(dark),
            borderRadius:
                BorderRadius.circular(MomentsSecondaryLayout.imageRadius),
            child: InkWell(
              key: const ValueKey('moments_add_images'),
              onTap: onPickPhotos,
              borderRadius:
                  BorderRadius.circular(MomentsSecondaryLayout.imageRadius),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                    minWidth: MomentsComposerSpacing.photoTile,
                    minHeight: MomentsComposerSpacing.photoTile),
                child: Padding(
                  padding:
                      const EdgeInsets.all(MomentsSecondaryLayout.avatarGap),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    picking
                        ? const SizedBox.square(
                            dimension: MomentsComposerSpacing.photoIcon,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.add_photo_alternate_outlined,
                            size: MomentsComposerSpacing.photoIcon,
                            color: onPickPhotos == null
                                ? MomentsTheme.secondary(dark)
                                : MomentsTheme.name(dark)),
                    const SizedBox(height: MomentsSecondaryLayout.gridGap),
                    Text(momentsText(context, zh: '相册', en: 'Photos'),
                        style: TextStyle(
                            color: MomentsTheme.secondary(dark),
                            fontSize: MomentsSecondaryLayout.metadataSize)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: MomentsComposerSpacing.sectionGap),
      Divider(height: 1, color: MomentsTheme.border(dark)),
      Semantics(
        button: true,
        enabled: onVisibility != null,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('moments_choose_visibility'),
            onTap: onVisibility,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  vertical: MomentsSecondaryLayout.pageInset),
              child: Row(children: [
                Icon(Icons.lock_outline_rounded,
                    size: MomentsSecondaryLayout.toolIcon,
                    color: MomentsTheme.name(dark)),
                const SizedBox(width: MomentsSecondaryLayout.avatarGap),
                Expanded(
                    flex: 3,
                    child: Text(
                        momentsText(context,
                            zh: '谁可以看', en: 'Who can see this'),
                        style: TextStyle(
                            color: MomentsTheme.text(dark),
                            fontSize: MomentsSecondaryLayout.captionSize))),
                const SizedBox(width: MomentsSecondaryLayout.gridGap),
                Expanded(
                    flex: 2,
                    child: Text(visibilityLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            color: MomentsTheme.secondary(dark),
                            fontSize: MomentsSecondaryLayout.metadataSize))),
                const SizedBox(width: MomentsSecondaryLayout.gridGap),
                Icon(Icons.chevron_right_rounded,
                    color: MomentsTheme.secondary(dark),
                    size: MomentsSecondaryLayout.toolIcon),
              ]),
            ),
          ),
        ),
      ),
      Divider(height: 1, color: MomentsTheme.border(dark)),
      const SizedBox(height: MomentsSecondaryLayout.pageInset),
      status,
    ]);
  }
}
