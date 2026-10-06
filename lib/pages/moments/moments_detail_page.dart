import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import 'moments_actions.dart';
import 'moments_likes_page.dart';
import 'moments_media_preview.dart';
import 'moments_widgets.dart';
import 'presentation/moments_engagement_panel.dart';
import 'presentation/moments_detail_comment_row.dart';

class MomentsDetailPage extends StatefulWidget {
  const MomentsDetailPage(
      {super.key,
      required this.repository,
      required this.momentId,
      this.onOpenAuthor});
  final MomentsRepository repository;
  final String momentId;
  final ValueChanged<MomentUser>? onOpenAuthor;
  @override
  State<MomentsDetailPage> createState() => _MomentsDetailPageState();
}

class _MomentsDetailPageState extends State<MomentsDetailPage> {
  final _scroll = ScrollController();
  late final String _scope;
  bool _loading = true;
  Future<void>? _loadWork;
  int _commentGeneration = 0;
  bool _liking = false;
  Object? _error;
  Object? _commentError;
  bool _retryCommentsRefresh = true;
  MomentPost? get _post => widget.repository.postById(widget.momentId);
  bool get _current => mounted && widget.repository.isSessionCurrent(_scope);
  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    widget.repository.retainDetail(widget.momentId);
    _scroll.addListener(_paginate);
    _load();
  }

  Future<void> _load() {
    if (!_current) return Future.value();
    final pending = _loadWork;
    if (pending != null) return pending;
    final work = _loadPostAndComments();
    _loadWork = work;
    return work.whenComplete(() => _loadWork = null);
  }

  Future<void> _loadPostAndComments() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.repository.loadDetail(widget.momentId, trackForSync: false);
      if (!_current) return;
      await _loadComments();
    } catch (error) {
      if (mounted && _current) {
        setState(() => _error = error);
        if (_post != null) {
          showMomentsFeedback(context, momentsErrorText(context, error));
        }
      }
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  Future<void> _loadComments({bool refresh = true}) async {
    if (!_current) return;
    final generation = ++_commentGeneration;
    setState(() {
      _commentError = null;
      _retryCommentsRefresh = refresh;
    });
    try {
      await widget.repository.loadComments(widget.momentId, refresh: refresh);
    } catch (error) {
      if (_current && generation == _commentGeneration) {
        setState(() => _commentError = error);
      }
    }
  }

  void _paginate() {
    final state = widget.repository.commentState(widget.momentId);
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 300 &&
        state.hasMore &&
        !_loading &&
        !state.loading &&
        state.error == null &&
        _commentError == null) {
      _loadComments(refresh: false);
    }
  }

  Future<void> _like(MomentPost post) async {
    if (_liking) return;
    setState(() => _liking = true);
    try {
      await widget.repository.setLiked(post.momentId, !post.likedByMe);
    } catch (error) {
      if (mounted && _current) {
        showMomentsFeedback(context, momentsErrorText(context, error));
      }
    } finally {
      if (_current) setState(() => _liking = false);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    widget.repository.releaseDetail(widget.momentId, sessionScope: _scope);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final post = _post;
        final comments = widget.repository.commentState(widget.momentId);
        final valid = widget.repository.isSessionCurrent(_scope);
        return MomentsScaffold(
            title: momentsText(context, zh: '详情', en: 'Details'),
            backgroundColor:
                MomentsTheme.detailBackground(momentsDark(context)),
            bottomNavigationBar: valid && post?.canComment == true
                ? SafeArea(
                    top: false,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppTokens.s5, vertical: AppTokens.s3),
                        child: OutlinedButton.icon(
                            onPressed: _loading
                                ? null
                                : () => showMomentsCommentSheet(
                                    context, widget.repository, post!),
                            icon: const Icon(Icons.edit_outlined),
                            label: Text(momentsText(context,
                                zh: '写评论…', en: 'Write a comment…')))))
                : null,
            body: valid && _loading && post == null
                ? const Center(child: CircularProgressIndicator())
                : post == null || !valid
                    ? MomentsStatePanel(
                        icon: Icons.article_outlined,
                        title: momentsText(context,
                            zh: '动态暂不可用', en: 'Post unavailable'),
                        message: _error != null
                            ? momentsErrorText(context, _error!)
                            : momentsText(context,
                                zh: '动态已删除或查看权限已变更',
                                en: 'This post was deleted or access changed.'),
                        onAction: valid ? _load : null,
                        actionLabel: valid
                            ? momentsText(context, zh: '重试', en: 'Retry')
                            : null)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: CustomScrollView(
                            controller: _scroll,
                            physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics()),
                            slivers: [
                              SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 18, 20, 0),
                                  sliver: SliverToBoxAdapter(
                                      child: MomentsPostCard(
                                          key: ValueKey(
                                              'moments_post_${post.momentId}'),
                                          repository: widget.repository,
                                          post: post,
                                          detail: true,
                                          busy: _liking,
                                          onOpen: () {},
                                          onAuthor: () => widget.onOpenAuthor
                                              ?.call(post.author),
                                          onLike: () => _like(post),
                                          onLikes: () => openMomentsLikes(
                                              context, widget.repository, post.momentId,
                                              onOpenAuthor:
                                                  widget.onOpenAuthor),
                                          onComment: () => showMomentsCommentSheet(
                                              context, widget.repository, post),
                                          onMedia: (index) =>
                                              openMomentsMedia(context, widget.repository, post, index),
                                          onCommentAction: (comment) => showMomentCommentActions(context, widget.repository, post, comment),
                                          onDelete: post.canDelete ? () => deleteMoment(context, widget.repository, post) : null,
                                          onVisibility: post.canEditVisibility ? () => changeMomentVisibility(context, widget.repository, post) : null,
                                          onReport: widget.repository.capabilities?.reportsEnabled == true ? () => reportMoment(context, widget.repository, post.momentId) : null))),
                              if (post.likesPreview.isNotEmpty)
                                SliverPadding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 8, 20, 0),
                                  sliver: SliverToBoxAdapter(
                                    child: MomentsEngagementPanel(
                                      post: post,
                                      detail: true,
                                      connectedComments:
                                          comments.items.isNotEmpty,
                                      onLikes: () => openMomentsLikes(context,
                                          widget.repository, post.momentId,
                                          onOpenAuthor: widget.onOpenAuthor),
                                      onCommentAction: (comment) =>
                                          showMomentCommentActions(context,
                                              widget.repository, post, comment),
                                    ),
                                  ),
                                ),
                              SliverPadding(
                                  padding: EdgeInsets.fromLTRB(20,
                                      post.likesPreview.isEmpty ? 8 : 0, 20, 0),
                                  sliver: SliverList.builder(
                                      itemCount: comments.items.length,
                                      itemBuilder: (context, index) {
                                        final comment = comments.items[index];
                                        return MomentsDetailCommentRow(
                                          key: ValueKey(comment.commentId),
                                          comment: comment,
                                          isFirst: index == 0,
                                          isLast: index ==
                                              comments.items.length - 1,
                                          startsPanel: index == 0 &&
                                              post.likesPreview.isEmpty,
                                          onAuthor: widget.onOpenAuthor == null
                                              ? null
                                              : () => widget.onOpenAuthor!(
                                                  comment.author),
                                          onAction: () =>
                                              showMomentCommentActions(
                                                  context,
                                                  widget.repository,
                                                  post,
                                                  comment),
                                        );
                                      })),
                              if (_error != null)
                                SliverToBoxAdapter(
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 20, vertical: 8),
                                        child: TextButton.icon(
                                            onPressed: _load,
                                            icon: const Icon(
                                                Icons.cloud_off_outlined),
                                            label: Text(momentsText(context,
                                                zh: '刷新失败，点击重试',
                                                en: 'Refresh failed. Retry'))))),
                              SliverToBoxAdapter(
                                  child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          20, 22, 20, 96),
                                      child: comments.loading
                                          ? const Center(
                                              child:
                                                  CircularProgressIndicator())
                                          : _commentError != null ||
                                                  comments.error != null
                                              ? MomentsStatePanel(
                                                  icon:
                                                      Icons.cloud_off_outlined,
                                                  title: momentsText(context,
                                                      zh: '评论加载失败',
                                                      en:
                                                          'Could not load comments'),
                                                  message: momentsErrorText(
                                                      context,
                                                      _commentError ??
                                                          comments.error!),
                                                  onAction: () => _loadComments(
                                                      refresh:
                                                          _retryCommentsRefresh),
                                                  actionLabel: momentsText(context,
                                                      zh: '重试', en: 'Retry'))
                                              : comments.hasMore
                                                  ? Center(
                                                      child: TextButton(
                                                          onPressed: () => _loadComments(
                                                              refresh: false),
                                                          child: Text(momentsText(context,
                                                              zh: '加载更多评论',
                                                              en:
                                                                  'Load more comments'))))
                                                  : Text(
                                                      comments.items.isEmpty && post.likesPreview.isEmpty
                                                          ? momentsText(context,
                                                              zh: '还没有互动',
                                                              en: 'No activity yet')
                                                          : '',
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(color: AppTokens.textSecondary(dark: momentsDark(context)), fontSize: 13)))),
                            ])));
      });
}
