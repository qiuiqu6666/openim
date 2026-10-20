import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:openim_common/localization.dart';
import 'media_share_icons.dart';
import 'recognition/media_image_recognition.dart';
import 'recognition/media_recognition_section.dart';

enum MediaAction { save, forward, favorite, gallery, viewInChat, delete }

/// Display data only; validation and forwarding belong to the caller.
class MediaShareRecipient {
  const MediaShareRecipient(
      {required this.id,
      required this.name,
      this.avatar,
      this.isGroup = false});
  final String id, name;
  final String? avatar;
  final bool isGroup;
}

class MediaSheetSelection {
  const MediaSheetSelection.action(this.action)
      : recipient = null, target = null, openTarget = false;
  const MediaSheetSelection.recipient(this.recipient)
      : action = null, target = null, openTarget = false;
  const MediaSheetSelection.recognized(this.target, this.openTarget)
      : action = null, recipient = null;
  final MediaAction? action;
  final MediaShareRecipient? recipient;
  final MediaRecognitionTarget? target;
  final bool openTarget;
}

/// Media-specific share surface; operations run after its route closes.
class MediaShareSheet extends StatefulWidget {
  const MediaShareSheet({
    super.key,
    required this.canSave,
    required this.canForward,
    required this.canViewInChat,
    required this.canDelete,
    this.canFavorite = false,
    this.canShowGallery = false,
    this.loadRecipients,
    this.recognize,
  });
  final bool canSave, canForward, canViewInChat, canDelete;
  final bool canFavorite, canShowGallery;
  final Future<List<MediaShareRecipient>> Function()? loadRecipients;
  final MediaRecognitionRequest Function()? recognize;

  @override
  State<MediaShareSheet> createState() => _MediaShareSheetState();
}

class _MediaShareSheetState extends State<MediaShareSheet> {
  late var _recipients = widget.loadRecipients == null
      ? null
      : Future<List<MediaShareRecipient>>.sync(widget.loadRecipients!);
  bool _closing = false;

  void _close([MediaSheetSelection? result]) {
    if (_closing || ModalRoute.of(context)?.isCurrent != true) return;
    _closing = true;
    Navigator.of(context).pop(result);
  }

  void _choose(MediaAction action) =>
      _close(MediaSheetSelection.action(action));

  Widget _tile(String label, Widget icon, VoidCallback onTap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final displayLabel = !zh
        ? label
        : label == 'mediaViewInChat'.tr
            ? AppCopy.text('聊天位置')
            : label == AppCopy.text('图片和视频')
                ? AppCopy.text('图库')
                : label == StrRes.saveToAlbum
                    ? AppCopy.text('保存')
                    : label;
    return SizedBox(
      width: _Tokens.itemWidth,
      child: TextButton(
        key: ValueKey('media-share-$label'),
        style: TextButton.styleFrom(
          foregroundColor: AppTokens.textSecondary(dark: dark),
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s2),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.rMd)),
        ),
        onPressed: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: _Tokens.iconBox,
            height: _Tokens.iconBox,
            decoration: BoxDecoration(
              color: AppTokens.surface(dark: dark),
              borderRadius: BorderRadius.circular(AppTokens.rLg),
            ),
            alignment: Alignment.center,
            child: ExcludeSemantics(child: icon),
          ),
          const SizedBox(height: AppTokens.s2),
          Text(displayLabel,
              semanticsLabel: label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: _Tokens.labelSize)),
        ]),
      ),
    );
  }

  Widget _action(String label, IconData icon, MediaAction action,
          [Color? color]) =>
      _tile(
          label,
          Icon(icon,
              size: _Tokens.iconSize,
              color: color ??
                  AppTokens.textPrimary(
                      dark: Theme.of(context).brightness == Brightness.dark)),
          () => _choose(action));

  Widget _row(List<Widget> children) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppTokens.s3),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      );

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final primary = [
      if (widget.canForward)
        _tile(
            StrRes.menuForward,
            SvgPicture.string(
              MediaShareIcons.forward,
              width: _Tokens.iconSize,
              height: _Tokens.iconSize,
              colorFilter: const ColorFilter.mode(
                  AppTokens.biometricGreen, BlendMode.srcIn),
            ),
            () => _choose(MediaAction.forward)),
      if (widget.canFavorite)
        _tile(
            AppCopy.text('收藏'),
            SvgPicture.string(
              MediaShareIcons.favorite,
              width: _Tokens.iconSize,
              height: _Tokens.iconSize,
            ),
            () => _choose(MediaAction.favorite)),
    ];
    final secondary = [
      if (widget.canSave)
        _action(StrRes.saveToAlbum, Icons.save_alt_rounded, MediaAction.save),
      if (widget.canViewInChat)
        _action('mediaViewInChat'.tr, Icons.chat_bubble_outline_rounded,
            MediaAction.viewInChat),
      if (widget.canShowGallery)
        _action(AppCopy.text('图片和视频'), Icons.grid_view_rounded,
            MediaAction.gallery),
      if (widget.canDelete)
        _tile(
            StrRes.delete,
            const ChatMessageMenuIcon(
                action: 'delete',
                color: AppTokens.danger,
                size: _Tokens.iconSize),
            () => _choose(MediaAction.delete)),
    ];
    return ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * _Tokens.maxHeight),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppTokens.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_recipients != null) ...[
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppTokens.s6),
                      child: Text('recentConversations'.tr,
                          style: TextStyle(
                              fontSize: AppTokens.secondaryFontSize,
                              fontWeight: FontWeight.w600,
                              color: AppTokens.textPrimary(dark: dark))),
                    ),
                    const SizedBox(height: AppTokens.s3),
                    FutureBuilder<List<MediaShareRecipient>>(
                      future: _recipients,
                      builder: (_, snapshot) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (snapshot.connectionState != ConnectionState.done)
                            const LinearProgressIndicator(),
                          if (snapshot.hasError)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.s5),
                              child: TextButton.icon(
                                onPressed: () => setState(() {
                                  _recipients =
                                      Future<List<MediaShareRecipient>>.sync(
                                          widget.loadRecipients!);
                                }),
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text('chatHistoryRetry'.tr),
                              ),
                            ),
                          if (snapshot.connectionState ==
                                  ConnectionState.done &&
                              !snapshot.hasError &&
                              (snapshot.data?.isEmpty ?? true))
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: AppTokens.s6),
                              child: Text(
                                Localizations.localeOf(context).languageCode ==
                                        'zh'
                                    ? AppCopy.text('暂无最近会话')
                                    : 'No recent conversations',
                                style: TextStyle(
                                    color: AppTokens.textSecondary(dark: dark)),
                              ),
                            ),
                          _row([
                            for (final recipient
                                in (snapshot.data ?? <MediaShareRecipient>[])
                                    .take(6))
                              _tile(
                                  recipient.name,
                                  AvatarView(
                                    width: _Tokens.iconBox,
                                    height: _Tokens.iconBox,
                                    url: recipient.avatar,
                                    text: recipient.name,
                                    isGroup: recipient.isGroup,
                                    isCircle: false,
                                    borderRadius:
                                        BorderRadius.circular(AppTokens.rSm),
                                  ),
                                  () => _close(MediaSheetSelection.recipient(
                                      recipient))),
                            if (widget.canForward)
                              _tile(
                                  AppCopy.text('更多'),
                                  Icon(Icons.add_rounded,
                                      size: _Tokens.iconSize,
                                      color:
                                          AppTokens.textSecondary(dark: dark)),
                                  () => _choose(MediaAction.forward)),
                          ]),
                        ],
                      ),
                    ),
                    Divider(
                        height: AppTokens.s5,
                        color: AppTokens.border(dark: dark)),
                  ],
                  if (primary.isNotEmpty) _row(primary),
                  if (primary.isNotEmpty && secondary.isNotEmpty)
                    const SizedBox(height: AppTokens.s5),
                  if (widget.recognize == null && secondary.isNotEmpty)
                    _row(secondary),
                  if (widget.recognize != null)
                    MediaRecognitionSection(
                      start: widget.recognize!,
                      tileBuilder: _tile,
                      actionsBuilder: (copyActions) =>
                          _row([...secondary, ...copyActions]),
                      onSelected: (target, open) =>
                          _close(MediaSheetSelection.recognized(target, open)),
                    ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: AppTokens.border(dark: dark)),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              key: ValueKey(
                  'media-share-${CupertinoLocalizations.of(context).cancelButtonLabel}'),
              style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(AppTokens.minimumTapSize),
                  foregroundColor: AppTokens.textSecondary(dark: dark)),
              onPressed: () => _close(),
              child: Text(CupertinoLocalizations.of(context).cancelButtonLabel,
                  style:
                      const TextStyle(fontSize: AppTokens.secondaryFontSize)),
            ),
          ),
        ]),
      ),
    );
  }
}

abstract final class _Tokens {
  static const itemWidth = 80.0;
  static const iconBox = 48.0;
  static const iconSize = 24.0;
  static const labelSize = 12.0;
  static const maxHeight = .85;
}
