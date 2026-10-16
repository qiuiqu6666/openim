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
    final next = offset < 0 ? -offset : 0.0;
    if ((next - _stretch).abs() < .5) return;
    setState(() => _stretch = next);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_scrollChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        key: const ValueKey('moments_cover'),
        height: MomentsLayout.headerHeight,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
              left: 0,
              right: 0,
              top: -_stretch,
              bottom: 0,
              child: ClipRect(
                  key: const ValueKey('moments_cover_surface'),
                  child: Stack(fit: StackFit.expand, children: [
                    Semantics(
                      button: widget.onCover != null,
                      label: momentsText(context,
                          zh: '朋友圈封面', en: 'Moments cover'),
                      child: GestureDetector(
                        onTap: widget.onCover,
                        child: Transform.scale(
                          scale: MediaQuery.disableAnimationsOf(context)
                              ? 1
                              : 1 + _stretch / MomentsLayout.coverHeight * .35,
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
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                MomentsTheme.coverScrim,
                                MomentsTheme.coverClear
                              ],
                            ),
                          ),
                        ),
                      ),
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
                                tooltip: MaterialLocalizations.of(context)
                                    .backButtonTooltip,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                                icon: const Icon(
                                    Icons.arrow_back_ios_new_rounded),
                                color: MomentsTheme.coverForeground,
                              ),
                              const Spacer(),
                              if (widget.onNotifications != null)
                                Stack(clipBehavior: Clip.none, children: [
                                  IconButton(
                                      tooltip: momentsText(context,
                                          zh: widget.unreadCount > 0
                                              ? '互动消息，${widget.unreadCount}条未读'
                                              : '互动消息',
                                          en: widget.unreadCount > 0
                                              ? 'Activity, ${widget.unreadCount} unread'
                                              : 'Activity'),
                                      onPressed: widget.onNotifications,
                                      icon: const Icon(
                                          Icons.notifications_none_rounded),
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
                                            color:
                                                MomentsTheme.notificationBadge,
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            border: Border.all(
                                                color: MomentsTheme
                                                    .coverForeground,
                                                width: 1.2)),
                                        child: Text(
                                            widget.unreadCount > 99
                                                ? '99+'
                                                : '${widget.unreadCount}',
                                            style: const TextStyle(
                                                color: MomentsTheme
                                                    .coverForeground,
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
            top: MomentsLayout.headerAvatarTop,
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
