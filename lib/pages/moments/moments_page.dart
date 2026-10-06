import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import '../mine/settings/widgets/settings_widgets.dart';
import 'moments_actions.dart';
import 'moments_compose_page.dart';
import 'moments_cover_page.dart';
import 'moments_detail_page.dart';
import 'moments_likes_page.dart';
import 'moments_media_preview.dart';
import 'moments_notifications_page.dart';
import 'moments_settings_page.dart';
import 'moments_widgets.dart';
import 'presentation/moments_cover_header.dart';
import 'presentation/moments_profile_timeline.dart';
import 'presentation/moments_profile_range_hint.dart';

/// Community entry and personal timelines share server-backed live entities.
class MomentsPage extends StatefulWidget {
  const MomentsPage(
      {super.key, this.repository, this.authorId, this.profileUser});
  final MomentsRepository? repository;
  final String? authorId;
  final MomentUser? profileUser;
  @override
  State<MomentsPage> createState() => _MomentsPageState();
}

class _MomentsPageState extends State<MomentsPage> {
  late final MomentsRepository _repository;
  late final String _scope;
  final _scroll = ScrollController();
  final Set<String> _busyLikes = {};
  bool _loading = false;
  bool _refreshing = false;
  int _loadGeneration = 0;
  Future<void>? _loadWork;
  Future<void>? _headerWork;
  bool _settingsAttempted = false;
  bool _initialLoaded = false;
  Object? _error;
  bool _retryRefresh = true;
  bool get _feed => widget.authorId == null;
  bool get _own => _feed || widget.authorId == _repository.currentUserId;
  MomentsQueryState get _state =>
      _feed ? _repository.feedState : _repository.userState(widget.authorId!);
  MomentUser get _profile =>
      _state.author ??
      widget.profileUser ??
      MomentUser(
          userId: widget.authorId ?? _repository.currentUserId,
          nickname:
              _own ? momentsText(context, zh: '我的朋友圈', en: 'My Moments') : '');
  bool get _current => mounted && _repository.isSessionCurrent(_scope);

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MomentsRepository.instance;
    _scope = _repository.sessionScope;
    _scroll.addListener(_paginate);
    _load();
  }

  Future<void> _load({bool refresh = true, bool forceCapabilities = false}) {
    if (!_current) return Future.value();
    final pending = _loadWork;
    if (pending != null && (!refresh || _refreshing)) return pending;
    // A pull refresh supersedes an old continuation; repository generations
    // discard its response, and this generation discards its local UI errors.
    final generation = ++_loadGeneration;
    _refreshing = refresh;
    final work = _loadQuery(refresh, forceCapabilities, generation);
    _loadWork = work;
    return work.whenComplete(() {
      if (generation == _loadGeneration) _loadWork = null;
    });
  }

  Future<void> _loadQuery(
      bool refresh, bool forceCapabilities, int generation) async {
    setState(() {
      _loading = true;
      _error = null;
      _retryRefresh = refresh;
    });
    try {
      if (refresh) {
        await _repository.ensureCapabilities(force: forceCapabilities);
        if (!_current || generation != _loadGeneration) return;
        if (_headerWork == null) _settingsAttempted = false;
      }
      if (!_feed && _own && _shouldLoadSettings) {
        // Resolve a personal timeline's range before revealing its rows: the
        // range hint otherwise gets inserted above already-visible content.
        await _loadCoverSettings();
        if (!_current || generation != _loadGeneration) return;
      }
      if (_feed) {
        await _repository.loadFeed(refresh: refresh);
      } else {
        await _repository.loadUser(widget.authorId!, refresh: refresh);
      }
      if (!_current || generation != _loadGeneration) return;
      setState(() => _initialLoaded = true);
      unawaited(_loadHeaderExtras(refreshNotifications: refresh));
    } catch (error) {
      if (_current && generation == _loadGeneration) {
        setState(() => _error = error);
      }
    } finally {
      if (_current && generation == _loadGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadHeaderExtras({required bool refreshNotifications}) {
    final pending = _headerWork;
    if (pending != null) return pending;
    final work = _loadHeaderData(refreshNotifications);
    _headerWork = work;
    return work.whenComplete(() => _headerWork = null);
  }

  Future<void> _loadHeaderData(bool refreshNotifications) async {
    if (!_current) return;
    if (_own && _shouldLoadSettings) await _loadCoverSettings();
    if (!_current) return;
    if (_feed && refreshNotifications) {
      try {
        await _repository.loadNotifications();
      } catch (_) {}
    }
  }

  bool get _shouldLoadSettings =>
      !_settingsAttempted &&
      _repository.settings == null &&
      _repository.capabilities?.settingsEnabled == true;

  Future<void> _loadCoverSettings() async {
    _settingsAttempted = true;
    // A cover failure must not turn an otherwise available list into an error.
    try {
      await _repository.loadSettings();
    } catch (_) {}
  }

  void _paginate() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 400 &&
        _state.hasMore &&
        !_state.loading &&
        !_loading &&
        _state.error == null &&
        _error == null) {
      _load(refresh: false);
    }
  }

  Future<void> _compose() async {
    final result = await Navigator.of(context).push<MomentPost>(
        MaterialPageRoute(
            builder: (_) => MomentsComposePage(
                repository: _repository,
                displayName: widget.profileUser?.displayName,
                avatarUrl: widget.profileUser?.avatarUrl)));
    if (result != null && mounted) await _load();
  }

  void _author(MomentUser author) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => MomentsPage(
              repository: _repository,
              authorId: author.userId,
              profileUser: author)));
  Future<void> _detail(String id) =>
      Navigator.of(context).push<void>(MaterialPageRoute(
          builder: (_) => MomentsDetailPage(
              repository: _repository, momentId: id, onOpenAuthor: _author)));
  Future<void> _settings() async {
    final previous = _repository.settings;
    final permissions = _repository.authorizationScope;
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => MomentsSettingsPage(repository: _repository)));
    if (!_current || _state.loading) return;
    final settings = _repository.settings;
    if (permissions != _repository.authorizationScope ||
        previous?.version != settings?.version ||
        previous?.visibleRangeDays != settings?.visibleRangeDays ||
        previous?.coverUrl != settings?.coverUrl) {
      await _load();
    }
  }

  Future<void> _cover() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => MomentsCoverPage(repository: _repository)));
    if (saved == true && _current && !_state.loading) await _load();
  }

  Future<void> _like(MomentPost post) async {
    if (!_busyLikes.add(post.momentId)) return;
    setState(() {});
    try {
      await _repository.setLiked(post.momentId, !post.likedByMe);
    } catch (error) {
      if (mounted && _current) {
        showMomentsFeedback(context, momentsErrorText(context, error));
      }
    } finally {
      _busyLikes.remove(post.momentId);
      if (_current) setState(() {});
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _repository,
      builder: (context, _) {
        final valid = _repository.isSessionCurrent(_scope);
        if (!valid) {
          return MomentsScaffold(
              title: momentsText(context, zh: '朋友圈', en: 'Moments'),
              body: MomentsStatePanel(
                  icon: Icons.lock_outline,
                  title: momentsText(context,
                      zh: '登录状态已变化', en: 'Account changed'),
                  message: momentsText(context,
                      zh: '请返回后重新进入朋友圈', en: 'Go back and reopen Moments.')));
        }
        final state = _state;
        final initialRangePending =
            !_feed && _own && !_initialLoaded && _loading;
        final title = _feed
            ? momentsText(context, zh: '朋友圈', en: 'Moments')
            : _own
                ? momentsText(context, zh: '我的朋友圈', en: 'My Moments')
                : momentsText(context,
                    zh: '${_profile.displayName}的朋友圈',
                    en: '${_profile.displayName}’s Moments');
        return MomentsScaffold(
            title: title,
            fullBleed: true,
            body: RefreshIndicator(
                onRefresh: () => _load(forceCapabilities: true),
                child: CustomScrollView(
                    controller: _scroll,
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    slivers: [
                      SliverToBoxAdapter(child: _header()),
                      if (!_feed && _own)
                        SliverToBoxAdapter(
                            child: MomentsTodayComposer(onTap: _compose)),
                      if (!_feed && _visibleRangeDays > 0)
                        SliverToBoxAdapter(
                            child: MomentsProfileRangeHint(
                                days: _visibleRangeDays,
                                onSettings: _own ? _settings : null)),
                      if (!valid)
                        SliverToBoxAdapter(
                            child: MomentsStatePanel(
                                icon: Icons.lock_outline,
                                title: momentsText(context,
                                    zh: '登录状态已变化', en: 'Account changed'),
                                message: momentsText(context,
                                    zh: '请返回后重新进入朋友圈',
                                    en: 'Go back and reopen Moments.')))
                      else if ((_loading || state.loading) &&
                          (state.items.isEmpty || initialRangePending))
                        const SliverToBoxAdapter(
                            child: Padding(
                                padding: EdgeInsets.all(AppTokens.s8),
                                child:
                                    Center(child: CircularProgressIndicator())))
                      else if (state.items.isEmpty &&
                          (_error != null || state.error != null))
                        SliverToBoxAdapter(
                            child: MomentsStatePanel(
                                icon: Icons.cloud_off_outlined,
                                title: (_error ?? state.error)
                                            is MomentsException &&
                                        ((_error ?? state.error)
                                                as MomentsException)
                                            .unavailable
                                    ? momentsText(context,
                                        zh: '朋友圈暂未开放',
                                        en: 'Moments is coming soon')
                                    : momentsText(context,
                                        zh: '暂时无法加载',
                                        en: 'Could not load Moments'),
                                message: momentsErrorText(
                                    context, _error ?? state.error!),
                                onAction: () => _load(forceCapabilities: true),
                                actionLabel: momentsText(context,
                                    zh: '重试', en: 'Retry')))
                      else if (state.items.isEmpty &&
                          _initialLoaded &&
                          !state.hasMore)
                        SliverFillRemaining(
                            hasScrollBody: false,
                            child: Center(
                                child: SettingsEmptyState(
                                    icon: Icons.inbox_outlined,
                                    imageWidth: 180,
                                    title: _feed
                                        ? momentsText(context,
                                            zh: '还没有朋友圈内容',
                                            en: 'No moments yet.')
                                        : momentsText(context,
                                            zh: '还没有发布朋友圈',
                                            en: 'No posts yet.'))))
                      else
                        SliverPadding(
                            padding: const EdgeInsets.fromLTRB(0, 4, 0, 24),
                            sliver: SliverList.builder(
                                itemCount: state.items.length,
                                itemBuilder: (context, index) {
                                  final post = state.items[index];
                                  if (!_feed) {
                                    final date =
                                        DateTime.fromMillisecondsSinceEpoch(
                                            post.createdAt);
                                    final previous = index == 0
                                        ? null
                                        : DateTime.fromMillisecondsSinceEpoch(
                                            state.items[index - 1].createdAt);
                                    final showDate = previous == null ||
                                        previous.year != date.year ||
                                        previous.month != date.month ||
                                        previous.day != date.day;
                                    return Column(children: [
                                      MomentsProfileTimelineItem(
                                        key: ValueKey(
                                            'moments_album_post_${post.momentId}'),
                                        repository: _repository,
                                        post: post,
                                        showDate: showDate,
                                        busy:
                                            _busyLikes.contains(post.momentId),
                                        onOpen: () => _detail(post.momentId),
                                        onMedia: (index) => openMomentsMedia(
                                            context, _repository, post, index),
                                        onLike: () => _like(post),
                                        onComment: () =>
                                            showMomentsCommentSheet(
                                                context, _repository, post),
                                        onLikes: () => openMomentsLikes(
                                            context, _repository, post.momentId,
                                            onOpenAuthor: _author),
                                      ),
                                      if (index < state.items.length - 1)
                                        Divider(
                                            height: 22,
                                            thickness: .6,
                                            indent: 96,
                                            color: MomentsTheme.border(
                                                momentsDark(context))),
                                    ]);
                                  }
                                  return Padding(
                                      key: ValueKey(post.momentId),
                                      padding: EdgeInsets.fromLTRB(
                                          10,
                                          0,
                                          10,
                                          index == state.items.length - 1
                                              ? 0
                                              : 10),
                                      child: MomentsPostCard(
                                          key: ValueKey(
                                              'moments_post_${post.momentId}'),
                                          repository: _repository,
                                          post: post,
                                          busy: _busyLikes
                                              .contains(post.momentId),
                                          onOpen: () => _detail(post.momentId),
                                          onAuthor: () => _author(post.author),
                                          onLike: () => _like(post),
                                          onLikes: () => openMomentsLikes(
                                              context, _repository, post.momentId,
                                              onOpenAuthor: _author),
                                          onComment: () => showMomentsCommentSheet(
                                              context, _repository, post),
                                          onMedia: (index) => openMomentsMedia(
                                              context, _repository, post, index),
                                          onCommentAction: (comment) => showMomentCommentActions(
                                              context, _repository, post, comment),
                                          onDelete: post.canDelete ? () => deleteMoment(context, _repository, post) : null,
                                          onVisibility: post.canEditVisibility ? () => changeMomentVisibility(context, _repository, post) : null,
                                          onReport: _repository.capabilities?.reportsEnabled == true ? () => reportMoment(context, _repository, post.momentId) : null));
                                })),
                      if (valid && state.items.isNotEmpty ||
                          valid && state.hasMore)
                        SliverToBoxAdapter(
                            child: Padding(
                                padding: const EdgeInsets.all(AppTokens.s5),
                                child: _loading || state.loading
                                    ? const Center(
                                        child: CircularProgressIndicator())
                                    : _error != null || state.error != null
                                        ? Column(children: [
                                            Text(
                                                momentsErrorText(context,
                                                    _error ?? state.error!),
                                                textAlign: TextAlign.center),
                                            TextButton(
                                                onPressed: () => _load(
                                                    refresh: _retryRefresh,
                                                    forceCapabilities:
                                                        _retryRefresh),
                                                child: Text(momentsText(context,
                                                    zh: '重试加载', en: 'Retry'))),
                                          ])
                                        : state.hasMore
                                            ? Center(
                                                child: TextButton(
                                                    onPressed: () =>
                                                        _load(refresh: false),
                                                    child: Text(momentsText(
                                                        context,
                                                        zh: '加载更多',
                                                        en: 'Load more'))))
                                            : Text(
                                                momentsText(context,
                                                    zh: '已经到底了',
                                                    en: 'You’re all caught up'),
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    color:
                                                        AppTokens.textSecondary(
                                                            dark: momentsDark(
                                                                context)),
                                                    fontSize: MomentsLayout
                                                        .captionSize)))),
                      const SliverToBoxAdapter(
                          child: SizedBox(height: MomentsLayout.footerSpace)),
                    ])));
      });

  int get _visibleRangeDays => _own
      ? _repository.settings?.visibleRangeDays ?? 0
      : _state.visibleRangeDays ?? 0;

  Widget _header() => MomentsCoverHeader(
        repository: _repository,
        profile: _profile,
        scrollController: _scroll,
        coverPath:
            _feed || _own ? _repository.settings?.coverUrl : _state.coverUrl,
        onCover: _own ? _cover : null,
        onProfile: _feed ? () => _author(_profile) : null,
        onCompose: _own ? _compose : null,
        onNotifications: _own
            ? () => Navigator.of(context).push<void>(MaterialPageRoute(
                builder: (_) => MomentsNotificationsPage(
                    repository: _repository, onOpenMoment: _detail)))
            : null,
        unreadCount: _repository.unreadCount,
      );
}
