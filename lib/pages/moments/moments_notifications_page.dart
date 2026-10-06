import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import 'moments_widgets.dart';
import 'presentation/moments_secondary_layout.dart';

/// Interactions are projected for the current account by [MomentsRepository].
class MomentsNotificationsPage extends StatefulWidget {
  const MomentsNotificationsPage({
    super.key,
    required this.repository,
    required this.onOpenMoment,
  });

  final MomentsRepository repository;
  final void Function(String) onOpenMoment;

  @override
  State<MomentsNotificationsPage> createState() =>
      _MomentsNotificationsPageState();
}

class _MomentsNotificationsPageState extends State<MomentsNotificationsPage> {
  bool _initialLoading = true;
  bool _markingRead = false;
  Object? _error;
  bool _retryRefresh = true;
  int _requestGeneration = 0;
  late String _scope;
  bool _opening = false;
  final Set<String> _readingItems = {};

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.addListener(_repositoryChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant MomentsNotificationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      oldWidget.repository.removeListener(_repositoryChanged);
      widget.repository.addListener(_repositoryChanged);
      _scope = widget.repository.sessionScope;
      _initialLoading = true;
      _opening = false;
      _readingItems.clear();
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_requestGeneration;
    widget.repository.removeListener(_repositoryChanged);
    super.dispose();
  }

  void _repositoryChanged() {
    if (!mounted) return;
    if (!widget.repository.isSessionCurrent(_scope)) {
      ++_requestGeneration;
      _scope = widget.repository.sessionScope;
      setState(() {
        _initialLoading = false;
        _markingRead = false;
        _opening = false;
        _readingItems.clear();
        _error = const MomentsException('会话已改变，请重新打开朋友圈', authRequired: true);
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _load({bool refresh = true}) async {
    final request = ++_requestGeneration;
    if (mounted) setState(() => _error = null);
    try {
      await widget.repository.loadNotifications(refresh: refresh);
    } catch (error) {
      if (mounted && request == _requestGeneration) {
        setState(() {
          _error = error;
          _retryRefresh = refresh;
        });
      }
    } finally {
      if (mounted && request == _requestGeneration) {
        setState(() => _initialLoading = false);
      }
    }
  }

  void _feedback(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(momentsErrorText(context, error))),
    );
  }

  Future<void> _readAll() async {
    if (_markingRead || widget.repository.seenWatermark == null) return;
    final scope = _scope;
    final repository = widget.repository;
    setState(() => _markingRead = true);
    try {
      // The repository captures and validates the last committed watermark;
      // notifications arriving after it remain unread.
      await widget.repository.markNotificationsRead(readAll: true);
    } catch (error) {
      if (widget.repository == repository &&
          repository.isSessionCurrent(scope)) {
        _feedback(error);
      }
    } finally {
      if (mounted &&
          widget.repository == repository &&
          repository.isSessionCurrent(scope)) {
        setState(() => _markingRead = false);
      }
    }
  }

  Future<void> _open(MomentNotification item) async {
    if (!item.available ||
        item.momentId.isEmpty ||
        _opening ||
        _readingItems.contains(item.notificationId) ||
        ModalRoute.of(context)?.isCurrent == false) {
      return;
    }
    _opening = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _opening = false;
    });
    final scope = _scope;
    final repository = widget.repository;
    widget.onOpenMoment(item.momentId);
    if (item.read) return;
    _readingItems.add(item.notificationId);
    try {
      // Opening one item never marks an unseen page or the whole inbox read.
      await widget.repository.markNotificationsRead(
        notificationIds: [item.notificationId],
      );
    } catch (error) {
      if (widget.repository == repository &&
          repository.isSessionCurrent(scope)) {
        _feedback(error);
      }
    } finally {
      if (widget.repository == repository &&
          repository.isSessionCurrent(scope)) {
        _readingItems.remove(item.notificationId);
      }
    }
  }

  String _interactionText(MomentNotification item) {
    final type = item.type.toUpperCase();
    if (type.contains('LIKE')) {
      return momentsText(context, zh: '赞了你的朋友圈', en: 'Liked your moment');
    }
    if (type.contains('REPLY')) {
      return momentsText(context, zh: '回复了评论', en: 'Replied to a comment');
    }
    return momentsText(context, zh: '评论了你的朋友圈', en: 'Commented on your moment');
  }

  @override
  Widget build(BuildContext context) {
    final repository = widget.repository;
    final items = repository.notifications;
    final loading = _initialLoading || repository.notificationsLoading;
    final error = _error ?? repository.notificationsError;
    final unavailable = error is MomentsException && error.unavailable;
    final dark = momentsDark(context);

    Widget content;
    if (loading && items.isEmpty) {
      content = const Center(child: CupertinoActivityIndicator());
    } else if (error == null && items.isEmpty) {
      content = LayoutBuilder(
          builder: (context, constraints) => RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: Center(
                          child: MomentsStatePanel(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: momentsText(context,
                            zh: '还没有互动消息', en: 'No interactions yet'),
                        message: momentsText(context,
                            zh: '好友的点赞、评论和回复会显示在这里。',
                            en: 'Likes, comments and replies from friends will appear here.'),
                      ))))));
    } else {
      content = RefreshIndicator(
        onRefresh: _load,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: items.length + (error != null ? 1 : 0) + 1,
          itemBuilder: (context, index) {
            if (error != null && index == 0) {
              return MomentsStatePanel(
                icon: unavailable
                    ? Icons.info_outline_rounded
                    : Icons.cloud_off_rounded,
                title: momentsText(context,
                    zh: unavailable ? '朋友圈尚未开放' : '互动消息加载失败',
                    en: unavailable
                        ? 'Moments is not available yet'
                        : 'Could not load interactions'),
                message: momentsErrorText(context, error),
                actionLabel: momentsText(context, zh: '重试', en: 'Retry'),
                onAction: loading
                    ? null
                    : () => unawaited(_load(refresh: _retryRefresh)),
              );
            }
            final rowIndex = index - (error != null ? 1 : 0);
            if (rowIndex < items.length) {
              return _NotificationRow(
                item: items[rowIndex],
                text: _interactionText(items[rowIndex]),
                onTap: () => unawaited(_open(items[rowIndex])),
                showDivider: rowIndex < items.length - 1,
              );
            }
            if (repository.notificationsHasMore) {
              return TextButton(
                onPressed:
                    loading ? null : () => unawaited(_load(refresh: false)),
                child: loading
                    ? const CupertinoActivityIndicator()
                    : Text(momentsText(context, zh: '加载更多', en: 'Load more')),
              );
            }
            if (items.isNotEmpty && error == null) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                    child: Text(
                  momentsText(context, zh: '没有更多了', en: 'No more interactions'),
                  style: TextStyle(
                      color: MomentsTheme.secondary(dark),
                      fontSize: MomentsSecondaryLayout.draftSize),
                )),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: MomentsTheme.detailBackground(dark),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: MomentsTheme.card(dark),
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          color: MomentsTheme.nav(dark),
        ),
        title: Text(momentsText(context, zh: '全部互动消息', en: 'All interactions'),
            style: TextStyle(
                color: MomentsTheme.text(dark),
                fontSize: MomentsSecondaryLayout.titleSize,
                fontWeight: FontWeight.w600)),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('moments_notifications_menu'),
            tooltip: momentsText(context, zh: '更多', en: 'More'),
            icon: _markingRead
                ? const CupertinoActivityIndicator()
                : Icon(Icons.more_horiz_rounded,
                    color: MomentsTheme.text(dark)),
            onSelected: (_) => unawaited(_readAll()),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'read-all',
                enabled: !loading &&
                    !_markingRead &&
                    repository.unreadCount > 0 &&
                    repository.seenWatermark != null,
                child: Text(momentsText(context, zh: '全部已读', en: 'Read all')),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints:
                const BoxConstraints(maxWidth: MomentsLayout.pageMaxWidth),
            child: Semantics(
              label: repository.unreadCount > 0
                  ? momentsText(context,
                      zh: '${repository.unreadCount} 条未读消息',
                      en: '${repository.unreadCount} unread interactions')
                  : null,
              liveRegion: true,
              child: SizedBox(width: double.infinity, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.item,
    required this.text,
    required this.onTap,
    required this.showDivider,
  });

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
                text: target.displayName,
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
      Material(
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
                      const SizedBox(width: MomentsSecondaryLayout.avatarGap),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(item.actor.displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: MomentsTheme.name(dark),
                                    fontSize: MomentsSecondaryLayout.nameSize,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            liked
                                ? Semantics(
                                    label: text,
                                    child: Icon(Icons.favorite_border_rounded,
                                        color: MomentsTheme.name(dark),
                                        size: 24))
                                : _message(context, dark, comment),
                            if (timestamp != null) ...[
                              const SizedBox(height: 5),
                              Text(timestamp,
                                  style: TextStyle(
                                      color: MomentsTheme.secondary(dark),
                                      fontSize:
                                          MomentsSecondaryLayout.captionSize)),
                            ],
                          ])),
                      const SizedBox(width: MomentsSecondaryLayout.avatarGap),
                      Container(
                        width: MomentsSecondaryLayout.notificationPreview,
                        height: MomentsSecondaryLayout.notificationPreview,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                            color: MomentsTheme.panel(dark),
                            borderRadius: BorderRadius.circular(
                                MomentsSecondaryLayout
                                    .notificationPreviewRadius)),
                        child: Text(
                            item.momentText.trim().isEmpty
                                ? momentsText(context, zh: '动态', en: 'Moment')
                                : item.momentText.trim(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: MomentsTheme.secondary(dark),
                                fontSize: MomentsSecondaryLayout.draftSize,
                                height: 1.2)),
                      ),
                    ]),
              ))),
      if (showDivider)
        Divider(
            height: 1,
            thickness: MomentsSecondaryLayout.notificationDividerWidth,
            indent: MomentsSecondaryLayout.notificationDividerIndent,
            color: MomentsTheme.border(dark)),
    ]);
  }
}
