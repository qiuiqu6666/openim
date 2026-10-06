import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import 'moments_widgets.dart';
import 'presentation/moments_secondary_layout.dart';

class MomentsLikesPage extends StatefulWidget {
  const MomentsLikesPage(
      {super.key,
      required this.repository,
      required this.momentId,
      this.onOpenAuthor});
  final MomentsRepository repository;
  final String momentId;
  final ValueChanged<MomentUser>? onOpenAuthor;
  @override
  State<MomentsLikesPage> createState() => _MomentsLikesPageState();
}

class _MomentsLikesPageState extends State<MomentsLikesPage> {
  late String _session;
  late String _authorization;
  final ScrollController _scroll = ScrollController();
  bool _postObserved = false;
  bool _postRemoved = false;
  List<MomentLike> _items = [];
  String? _cursor;
  String _pageContext = '';
  bool _hasMore = false;
  bool _loading = true;
  bool _retryRefresh = true;
  int _generation = 0;
  Object? _error;
  @override
  void initState() {
    super.initState();
    _scroll.addListener(_loadNearEnd);
    _reset();
  }

  void _reset() {
    _session = widget.repository.sessionScope;
    _authorization = widget.repository.authorizationScope;
    _postObserved = widget.repository.postById(widget.momentId) != null;
    _postRemoved = false;
    _items = [];
    _cursor = null;
    _pageContext = '';
    _hasMore = false;
    _error = null;
    _loading = false;
    widget.repository.addListener(_permissionChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(MomentsLikesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.momentId != widget.momentId) {
      oldWidget.repository.removeListener(_permissionChanged);
      _generation++;
      _reset();
      if (_scroll.hasClients) _scroll.jumpTo(0);
    }
  }

  void _loadNearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < MomentsLayout.coverHeight &&
        _hasMore &&
        !_loading &&
        _error == null) {
      unawaited(_load(refresh: false));
    }
  }

  void _permissionChanged() {
    final hasPost = widget.repository.postById(widget.momentId) != null;
    _postObserved = _postObserved || hasPost;
    final removed = _postObserved && !hasPost;
    if (_authorization == widget.repository.authorizationScope &&
        removed == _postRemoved) {
      return;
    }
    final invalidate =
        removed || _authorization != widget.repository.authorizationScope;
    _postRemoved = removed;
    if (!invalidate) {
      if (mounted) setState(() {});
      return;
    }
    _generation++;
    _authorization = widget.repository.authorizationScope;
    if (mounted) {
      setState(() {
        _items = [];
        _cursor = null;
        _pageContext = '';
        _hasMore = false;
        _loading = false;
        _error = const MomentsException('查看权限已变更', permissionDenied: true);
      });
    }
  }

  Future<void> _load({bool refresh = true}) async {
    if (_loading ||
        _postRemoved ||
        !widget.repository.isSessionCurrent(_session)) {
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _retryRefresh = refresh;
    });
    try {
      var page = await widget.repository
          .loadLikes(widget.momentId, cursor: refresh ? null : _cursor);
      if (!mounted ||
          generation != _generation ||
          _authorization != widget.repository.authorizationScope ||
          !widget.repository.isSessionCurrent(_session)) {
        return;
      }
      final contextChanged = !refresh &&
          _pageContext.isNotEmpty &&
          page.viewerContextVersion.isNotEmpty &&
          _pageContext != page.viewerContextVersion;
      if (contextChanged) {
        setState(() {
          _items = [];
          _cursor = null;
          _hasMore = false;
          _pageContext = '';
          _retryRefresh = true;
        });
        page = await widget.repository.loadLikes(widget.momentId);
        if (!mounted ||
            generation != _generation ||
            _authorization != widget.repository.authorizationScope ||
            !widget.repository.isSessionCurrent(_session)) {
          return;
        }
      }
      setState(() {
        _items = {
          if (!refresh && !contextChanged)
            for (final item in _items) item.user.userId: item,
          for (final item in page.items) item.user.userId: item,
        }.values.toList();
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _pageContext = page.viewerContextVersion;
      });
    } catch (error) {
      if (mounted &&
          generation == _generation &&
          widget.repository.isSessionCurrent(_session)) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.repository.removeListener(_permissionChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    return MomentsScaffold(
        title: momentsText(context, zh: '点赞', en: 'Likes'),
        backgroundColor: MomentsTheme.card(dark),
        body: RefreshIndicator(
            onRefresh: () => _load(),
            child: ListView.builder(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _items.length + 1,
                itemBuilder: (context, index) {
                  if (index < _items.length) {
                    final user = _items[index].user;
                    return Column(children: [
                      InkWell(
                        onTap: widget.onOpenAuthor == null
                            ? null
                            : () => widget.onOpenAuthor!(user),
                        child: Padding(
                          padding: MomentsSecondaryLayout.friendInset,
                          child: Row(children: [
                            AvatarView(
                                url: user.avatarUrl,
                                text: user.displayName,
                                width: MomentsSecondaryLayout.avatarSize,
                                height: MomentsSecondaryLayout.avatarSize),
                            const SizedBox(
                                width: MomentsSecondaryLayout.avatarGap),
                            Expanded(
                                child: Text(user.displayName,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize:
                                            MomentsSecondaryLayout.nameSize,
                                        fontWeight: FontWeight.w600,
                                        color: MomentsTheme.text(dark)))),
                          ]),
                        ),
                      ),
                      if (index < _items.length - 1)
                        Divider(
                            height: 0,
                            thickness:
                                MomentsSecondaryLayout.friendDividerWidth,
                            color: MomentsTheme.border(dark)),
                    ]);
                  }
                  if (_loading) {
                    return const Padding(
                        padding: EdgeInsets.all(AppTokens.s8),
                        child: Center(child: CircularProgressIndicator()));
                  }
                  if (_error != null) {
                    return MomentsStatePanel(
                        icon: Icons.favorite_border,
                        title: momentsText(context,
                            zh: '点赞暂不可用', en: 'Likes unavailable'),
                        message: momentsErrorText(context, _error!),
                        onAction: !_postRemoved &&
                                widget.repository.isSessionCurrent(_session)
                            ? () => _load(refresh: _retryRefresh)
                            : null,
                        actionLabel:
                            momentsText(context, zh: '重试', en: 'Retry'));
                  }
                  if (_hasMore) {
                    return Padding(
                        padding: const EdgeInsets.all(AppTokens.s5),
                        child: Center(
                            child: TextButton(
                                onPressed: () => _load(refresh: false),
                                child: Text(momentsText(context,
                                    zh: '加载更多', en: 'Load more')))));
                  }
                  if (_items.isNotEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(MomentsLayout.footerSpace),
                      child: Text(
                          momentsText(context,
                              zh: '仅显示你自己和好友的点赞',
                              en:
                                  'Only your likes and friends’ likes are shown.'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: MomentsLayout.timeSize,
                              color: MomentsTheme.secondary(dark))),
                    );
                  }
                  return MomentsStatePanel(
                      icon: Icons.favorite_border,
                      title: _items.isEmpty
                          ? momentsText(context,
                              zh: '还没有可见点赞', en: 'No visible likes yet')
                          : momentsText(context,
                              zh: '已显示全部可见点赞', en: 'All visible likes loaded'),
                      message: momentsText(context,
                          zh: '仅显示你自己和好友的点赞',
                          en: 'Only your likes and friends’ likes are shown.'));
                })));
  }
}

Future<void> openMomentsLikes(
        BuildContext context, MomentsRepository repository, String momentId,
        {ValueChanged<MomentUser>? onOpenAuthor}) =>
    Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => MomentsLikesPage(
            repository: repository,
            momentId: momentId,
            onOpenAuthor: onOpenAuthor)));
