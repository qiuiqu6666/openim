import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../services/favorite_repository.dart';
import '../../../mine/secondary/favorites_page.dart'
    show favoriteKindLabel, favoriteKindIcon, favoriteStatusLabel;
import '../../../favorites/media/favorite_item_thumbnail.dart';
import '../../../mine/settings/widgets/settings_widgets.dart';

class FavoritePickerItemTile extends StatelessWidget {
  const FavoritePickerItemTile(
      {super.key,
      required this.item,
      required this.repository,
      required this.onTap,
      this.trailing});
  final FavoriteItem item;
  final FavoriteRepository repository;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final muted = AppTokens.textSecondary(dark: dark);
    String text(String zh, String en) => settingsText(context, zh: zh, en: en);
    final isText = {FavoriteKind.text, FavoriteKind.note, FavoriteKind.link}
        .contains(item.kind);
    final isAudio = item.kind == FavoriteKind.audio;
    final title = item.summary.trim().isNotEmpty
        ? item.summary
        : item.title.trim().isNotEmpty
            ? item.title
            : favoriteKindLabel(context, item.kind);
    final source = item.source?.displayName?.trim();
    final date = item.createdAt?.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    final status = favoriteStatusLabel(context, item);
    return Material(
      color: FavoritePickerTokens.card(dark: dark),
      borderRadius: BorderRadius.circular(FavoritePickerTokens.cardRadius),
      clipBehavior: Clip.antiAlias,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
            child: InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.s4),
                  child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                              crossAxisAlignment: isAudio
                                  ? CrossAxisAlignment.center
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                    width: isAudio
                                        ? (constraints.maxWidth / 2).clamp(
                                            FavoriteMediaTokens.audioHeight,
                                            FavoriteMediaTokens.audioWidth)
                                        : isText
                                            ? FavoritePickerTokens
                                                .textThumbnailSize
                                            : FavoritePickerTokens.mediaWidth,
                                    height: isAudio
                                        ? FavoriteMediaTokens.audioHeight
                                        : isText
                                            ? FavoritePickerTokens
                                                .textThumbnailSize
                                            : FavoritePickerTokens.mediaHeight,
                                    decoration: BoxDecoration(
                                        color: FavoritePickerTokens.textThumbnail(
                                            dark: dark),
                                        borderRadius: BorderRadius.circular(
                                            isText
                                                ? FavoritePickerTokens
                                                    .textThumbnailRadius
                                                : AppTokens.rMd)),
                                    clipBehavior: Clip.antiAlias,
                                    child: {
                                      FavoriteKind.image,
                                      FavoriteKind.video,
                                      FavoriteKind.audio
                                    }.contains(item.kind)
                                        ? FavoriteItemThumbnail(
                                            key: ValueKey(
                                                '${item.id}:${item.version}'),
                                            repository: repository,
                                            item: item)
                                        : Icon(
                                            isText
                                                ? Icons.title_rounded
                                                : favoriteKindIcon(item.kind),
                                            color: FavoritePickerTokens
                                                .thumbnailIcon,
                                            size: FavoritePickerTokens
                                                .closeIconSize)),
                                const SizedBox(
                                    width: FavoritePickerTokens.listPadding),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(title,
                                          maxLines: isText ? 4 : 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: FavoritePickerTokens
                                                  .previewFontSize,
                                              height: FavoritePickerTokens
                                                  .previewLineHeight,
                                              color: AppTokens.textPrimary(
                                                  dark: dark))),
                                      const SizedBox(
                                          height:
                                              FavoritePickerTokens.sourceGap),
                                      Text(
                                          text(
                                              '来源：${source?.isNotEmpty == true ? source : item.source != null ? text('聊天消息', 'Chat message') : text('手动添加', 'Manual')}',
                                              'Source: ${source?.isNotEmpty == true ? source : item.source != null ? 'Chat message' : 'Manual'}'),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: FavoritePickerTokens
                                                  .metadataFontSize,
                                              color: muted)),
                                      if (date != null) ...[
                                        const SizedBox(
                                            height:
                                                FavoritePickerTokens.dateGap),
                                        Text(
                                            '${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}',
                                            style: TextStyle(
                                                fontSize: FavoritePickerTokens
                                                    .metadataFontSize,
                                                color: muted)),
                                      ],
                                      if (status.isNotEmpty)
                                        Text(status,
                                            style: TextStyle(
                                                fontSize: FavoritePickerTokens
                                                    .metadataFontSize,
                                                color: muted)),
                                    ])),
                              ])),
                ))),
        if (trailing != null)
          Padding(
              padding: const EdgeInsets.fromLTRB(
                  0, AppTokens.s4, AppTokens.s4, AppTokens.s4),
              child: trailing!),
      ]),
    );
  }
}
