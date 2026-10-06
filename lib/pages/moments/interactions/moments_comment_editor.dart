import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:uuid/uuid.dart';
import '../../../services/moments_repository.dart';
import '../presentation/moments_text.dart';
import '../presentation/moments_theme.dart';
import '../presentation/moments_state_panel.dart';

Future<void> showMomentsCommentSheet(
        BuildContext context, MomentsRepository repository, MomentPost post,
        {MomentComment? replyTo}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: MomentsTheme.card(momentsDark(context)),
      builder: (_) =>
          _CommentEditor(repository: repository, post: post, replyTo: replyTo),
    );

class _CommentEditor extends StatefulWidget {
  const _CommentEditor(
      {required this.repository, required this.post, this.replyTo});
  final MomentsRepository repository;
  final MomentPost post;
  final MomentComment? replyTo;
  @override
  State<_CommentEditor> createState() => _CommentEditorState();
}

class _CommentEditorState extends State<_CommentEditor> {
  final _text = TextEditingController();
  late final String _scope;
  late String _authorization;
  bool _hadCanonicalPost = false;
  bool _permissionUnavailable = false;
  String _requestId = const Uuid().v4();
  bool _sending = false;
  bool _unknown = false;
  String? _submittedText;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scope = widget.repository.sessionScope;
    _authorization = widget.repository.authorizationScope;
    _hadCanonicalPost =
        widget.repository.postById(widget.post.momentId) != null;
    widget.repository.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (!widget.repository.isSessionCurrent(_scope)) {
      _text.clear();
      _submittedText = null;
      setState(() {});
      return;
    }
    final authorization = widget.repository.authorizationScope;
    final post = widget.repository.postById(widget.post.momentId);
    final replyVisible = widget.replyTo == null ||
        widget.repository.commentVisible(widget.replyTo!);
    final revoked = !replyVisible ||
        (_hadCanonicalPost && post == null) ||
        (post != null && !post.canComment) ||
        (authorization != _authorization && post == null);
    _authorization = authorization;
    _hadCanonicalPost = _hadCanonicalPost || post != null;
    if (revoked && !_permissionUnavailable) {
      _text.clear();
      _submittedText = null;
      setState(() => _permissionUnavailable = true);
    }
  }

  void _closeOwnSheet() {
    if (!mounted || !widget.repository.isSessionCurrent(_scope)) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isActive) return;
    final navigator = Navigator.of(context);
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_sessionChanged);
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!widget.repository.isSessionCurrent(_scope) || _permissionUnavailable) {
      return;
    }
    final text = _submittedText ?? _text.text.trim();
    if (text.isEmpty || text.runes.length > 500 || _sending) return;
    var confirmingUnknown = _unknown;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      if (_unknown) {
        final result =
            await widget.repository.api.queryCommentResult(_requestId);
        if (!mounted ||
            !widget.repository.isSessionCurrent(_scope) ||
            _permissionUnavailable) {
          return;
        }
        if (result.succeeded) {
          try {
            await widget.repository
                .loadDetail(widget.post.momentId, trackForSync: false);
            await widget.repository.loadComments(widget.post.momentId);
          } catch (_) {}
          if (mounted && widget.repository.isSessionCurrent(_scope)) {
            _closeOwnSheet();
          }
          return;
        }
        if (result.rejected) {
          confirmingUnknown = false;
          setState(() {
            _unknown = false;
            _submittedText = null;
            _requestId = const Uuid().v4();
            _error = momentsText(context,
                zh: '评论未发送，请修改后重试',
                en: 'The comment was not sent. Edit and try again.');
          });
          return;
        }
        if (!result.notFound) {
          throw const MomentsException('评论提交结果尚未确认', unknownResult: true);
        }
        // NOT_FOUND may race a delayed write: always resend the identical key.
      }
      if (!mounted ||
          !widget.repository.isSessionCurrent(_scope) ||
          _permissionUnavailable) {
        return;
      }
      await widget.repository.addComment(widget.post.momentId,
          text: text,
          clientRequestId: _requestId,
          replyToCommentId: widget.replyTo?.commentId);
      _closeOwnSheet();
    } catch (error) {
      if (!mounted ||
          !widget.repository.isSessionCurrent(_scope) ||
          _permissionUnavailable) {
        return;
      }
      setState(() {
        _unknown = confirmingUnknown ||
            error is MomentsException && error.unknownResult;
        if (_unknown) _submittedText = text;
        if (!_unknown) {
          _submittedText = null;
          _requestId = const Uuid().v4();
        }
        _error = momentsErrorText(context, error);
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = momentsDark(context);
    if (!widget.repository.isSessionCurrent(_scope)) {
      return MomentsStatePanel(
          icon: Icons.lock_outline,
          title: momentsText(context, zh: '登录状态已变化', en: 'Account changed'),
          message: momentsText(context,
              zh: '请关闭后重新进入朋友圈', en: 'Close this sheet and reopen Moments.'));
    }
    if (_permissionUnavailable) {
      return MomentsStatePanel(
          icon: Icons.lock_outline,
          title: momentsText(context, zh: '评论暂不可用', en: 'Comment unavailable'),
          message: momentsText(context,
              zh: '动态或回复对象已不可用，请关闭后重新查看。',
              en: 'The post or reply is unavailable. Close this sheet and reopen the post.'));
    }
    return PopScope(
      canPop: !_sending,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppTokens.s5, AppTokens.s3, AppTokens.s5,
            MediaQuery.viewInsetsOf(context).bottom + AppTokens.s5),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    widget.replyTo == null
                        ? momentsText(context, zh: '写评论', en: 'Add a comment')
                        : momentsText(context,
                            zh: '回复 ${widget.replyTo!.author.displayName}',
                            en:
                                'Reply to ${widget.replyTo!.author.displayName}'),
                    style: TextStyle(
                        color: MomentsTheme.text(dark),
                        fontSize: MomentsLayout.nameSize,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: AppTokens.s4),
                TextField(
                  controller: _text,
                  autofocus: true,
                  minLines: 2,
                  maxLines: 5,
                  readOnly: _sending || _unknown,
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(color: MomentsTheme.text(dark)),
                  decoration: InputDecoration(
                    hintText: momentsText(context,
                        zh: '说点什么…', en: 'Write something…'),
                    filled: true,
                    fillColor: MomentsTheme.panel(dark),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppTokens.rSm),
                        borderSide: BorderSide.none),
                    counterText: '${_text.text.trim().runes.length}/500',
                    errorText: _text.text.trim().runes.length > 500
                        ? momentsText(context,
                            zh: '评论最多 500 个字符',
                            en: 'Use at most 500 characters')
                        : null,
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.s3),
                    child: Text(_error!,
                        style: const TextStyle(color: AppTokens.danger)),
                  ),
                const SizedBox(height: AppTokens.s4),
                Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _sending ||
                              _text.text.trim().isEmpty ||
                              _text.text.trim().runes.length > 500
                          ? null
                          : _send,
                      child: _sending
                          ? const SizedBox.square(
                              dimension: AppTokens.s6,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_unknown
                              ? momentsText(context,
                                  zh: '确认并重试', en: 'Confirm and retry')
                              : momentsText(context, zh: '发送', en: 'Send')),
                    )),
              ]),
        ),
      ),
    );
  }
}
