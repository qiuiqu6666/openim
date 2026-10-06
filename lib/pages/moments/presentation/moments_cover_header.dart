import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import '../media/moments_media_image.dart';
import 'moments_text.dart';
import 'moments_theme.dart';

class MomentsCoverHeader extends StatefulWidget {
  const MomentsCoverHeader({
    super.key,
    required this.repository,
    required this.profile,
    required this.scrollController,
    this.coverPath,
    this.onCover,
    this.onProfile,
    this.onCompose,
    this.onNotifications,
    this.unreadCount = 0,
  });

  final MomentsRepository repository;
  final MomentUser profile;
  final ScrollController scrollController;
  final String? coverPath;
  final VoidCallback? onCover, onProfile, onCompose, onNotifications;
  final int unreadCount;

  @override
  State<MomentsCoverHeader> createState() => _MomentsCoverHeaderState();
}

class _MomentsCoverHeaderState extends State<MomentsCoverHeader> {
  double _stretch = 0;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_scrollChanged);
  }

  @override
  void didUpdateWidget(MomentsCoverHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_scrollChanged);
      widget.scrollController.addListener(_scrollChanged);
      _stretch = 0;
    }
  }

  void _scrollChanged() {
    if (!widget.scrollController.hasClients) return;
    final offset = widget.scrollController.offset;
    final next =
        !MediaQuery.disableAnimationsOf(context) && offset < 0 ? -offset : 0.0;
    if ((next - _stretch).abs() < .5) return;
    setState(() => _stretch = next);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) _stretch = 0;
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scrollChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('moments_cover'),
        height: MomentsLayout.headerHeight + _stretch,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(
              child: ClipRect(
                  child: Stack(fit: StackFit.expand, children: [
            Semantics(
              button: widget.onCover != null,
              label: momentsText(context, zh: '朋友圈封面', en: 'Moments cover'),
              child: GestureDetector(
                onTap: widget.onCover,
                child: Transform.scale(
                  scale: 1 + _stretch / MomentsLayout.coverHeight * .35,
                  alignment: Alignment.topCenter,
                  child: widget.coverPath?.isNotEmpty == true
                      ? MomentsMediaImage(
                          repository: widget.repository,
                          media: MomentMedia(
                              mediaId: 'cover:${widget.profile.userId}',
                              contentPath: widget.coverPath!),
                          thumbnail: false)
                      : Image.asset(MomentsLayout.coverAsset,
                          package: 'openim_common', fit: BoxFit.cover),
                ),
              ),
            ),
            Positioned(
              left: 28,
              right: 96,
              top: MediaQuery.paddingOf(context).top + 64,
              child: IgnorePointer(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        momentsText(context,
                            zh: '生活很美好', en: 'Life is beautiful'),
                        key: const ValueKey('moments_header_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: MomentsTheme.coverForeground,
                            fontSize: 24,
                            fontWeight: FontWeight.w300,
                            shadows: [
                              Shadow(
                                  color: MomentsTheme.coverShadow,
                                  blurRadius: 8)
                            ])),
                    const SizedBox(height: 6),
                    Text(
                        momentsText(context,
                            zh: '记录每一个平凡的日子', en: 'Record each ordinary day'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: MomentsTheme.coverSecondary,
                            fontSize: 13,
                            shadows: [
                              Shadow(
                                  color: MomentsTheme.coverShadow,
                                  blurRadius: 8)
                            ])),
                  ])),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(children: [
                      IconButton(
                        tooltip:
                            MaterialLocalizations.of(context).backButtonTooltip,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        color: MomentsTheme.coverForeground,
                      ),
                      const Spacer(),
                      if (widget.onNotifications != null)
                        Stack(clipBehavior: Clip.none, children: [
                          IconButton(
                              tooltip: momentsText(context,
                                  zh: '互动消息', en: 'Activity'),
                              onPressed: widget.onNotifications,
                              icon:
                                  const Icon(Icons.notifications_none_rounded),
                              color: MomentsTheme.coverForeground),
                          if (widget.unreadCount > 0)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: IgnorePointer(
                                  child: Container(
                                constraints: const BoxConstraints(
                                    minWidth: 16, minHeight: 16),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                    color: MomentsTheme.notificationBadge,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: MomentsTheme.coverForeground,
                                        width: 1.2)),
                                child: Text(
                                    widget.unreadCount > 99
                                        ? '99+'
                                        : '${widget.unreadCount}',
                                    style: const TextStyle(
                                        color: MomentsTheme.coverForeground,
                                        fontSize: 10,
                                        height: 1,
                                        fontWeight: FontWeight.w700)),
                              )),
                            ),
                        ]),
                      if (widget.onCompose != null)
                        IconButton(
                            tooltip: momentsText(context,
                                zh: '发布动态', en: 'Create post'),
                            onPressed: widget.onCompose,
                            icon: const Icon(Icons.camera_alt_outlined),
                            color: MomentsTheme.coverForeground),
                    ]),
                  )),
            ),
          ]))),
          Positioned(
            right: 16,
            top: MomentsLayout.headerAvatarTop + _stretch,
            child: Tooltip(
              message: widget.profile.displayName,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: MomentsTheme.coverForeground,
                    shape: BoxShape.circle),
                child: AvatarView(
                    key: const ValueKey('moments_header_avatar'),
                    width: MomentsLayout.headerAvatarSize,
                    height: MomentsLayout.headerAvatarSize,
                    isCircle: true,
                    url: widget.profile.avatarUrl,
                    text: widget.profile.displayName,
                    onTap: widget.onProfile),
              ),
            ),
          ),
        ]),
      );
}
