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
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
              border: InputBorder.none,
              hintText: momentsText(context,
                  zh: '这一刻的想法...', en: 'What is on your mind...'),
              hintStyle: TextStyle(color: MomentsTheme.secondary(dark)),
              errorText: controller.text.trim().runes.length > maxText
                  ? momentsText(context,
                      zh: '正文最多 $maxText 个字',
                      en: 'Use no more than $maxText characters')
                  : null),
          style: TextStyle(
              color: MomentsTheme.text(dark),
              fontSize: MomentsSecondaryLayout.nameSize,
              height: MomentsSecondaryLayout.bodyHeight)),
      const SizedBox(height: MomentsSecondaryLayout.avatarGap),
      if (media != null) media!,
      const SizedBox(height: MomentsSecondaryLayout.avatarGap),
      Material(
          color: Colors.transparent,
          child: InkWell(
              key: const ValueKey('moments_choose_visibility'),
              onTap: onVisibility,
              child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(children: [
                    Icon(Icons.lock_outline_rounded,
                        size: MomentsSecondaryLayout.toolIcon,
                        color: MomentsTheme.name(dark)),
                    const SizedBox(width: MomentsSecondaryLayout.gridGap),
                    Expanded(
                        child: Text(
                            momentsText(context,
                                zh: '谁可以看', en: 'Who can see this'),
                            style: TextStyle(
                                color: MomentsTheme.text(dark),
                                fontSize: MomentsSecondaryLayout.captionSize,
                                fontWeight: FontWeight.w600))),
                    Flexible(
                        child: Text(visibilityLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                color: MomentsTheme.secondary(dark),
                                fontSize:
                                    MomentsSecondaryLayout.metadataSize))),
                    Icon(Icons.chevron_right_rounded,
                        color: MomentsTheme.secondary(dark), size: 20),
                  ])))),
      const SizedBox(height: MomentsSecondaryLayout.avatarGap),
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Material(
            color: MomentsTheme.card(dark),
            borderRadius:
                BorderRadius.circular(MomentsSecondaryLayout.imageRadius),
            child: InkWell(
                key: const ValueKey('moments_add_images'),
                borderRadius:
                    BorderRadius.circular(MomentsSecondaryLayout.imageRadius),
                onTap: onPickPhotos,
                child: Container(
                    constraints: const BoxConstraints(
                        minHeight: MomentsSecondaryLayout.toolHeight),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                            MomentsSecondaryLayout.imageRadius),
                        border: Border.all(color: MomentsTheme.border(dark))),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      picking
                          ? const SizedBox.square(
                              dimension: MomentsSecondaryLayout.toolIcon,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.photo_library_outlined,
                              size: MomentsSecondaryLayout.toolIcon,
                              color: onPickPhotos == null
                                  ? MomentsTheme.secondary(dark)
                                  : MomentsTheme.name(dark)),
                      const SizedBox(width: 6),
                      Text(momentsText(context, zh: '相册', en: 'Photos'),
                          style: TextStyle(
                              color: MomentsTheme.text(dark),
                              fontSize: MomentsSecondaryLayout.captionSize)),
                    ])))),
        const SizedBox(width: MomentsSecondaryLayout.avatarGap),
        Expanded(child: Align(alignment: Alignment.centerRight, child: status)),
      ]),
    ]);
  }
}
