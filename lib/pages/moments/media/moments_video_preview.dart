import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import '../moments_widgets.dart';

/// Streams an existing authorized video; no public URL, download menu or shared
/// disk cache. This does not enable composing/uploading new video moments.
class MomentsVideoPreview extends StatefulWidget {
  const MomentsVideoPreview(
      {super.key,
      required this.repository,
      required this.post,
      required this.media});
  final MomentsRepository repository;
  final MomentPost post;
  final MomentMedia media;

  @override
  State<MomentsVideoPreview> createState() => _MomentsVideoPreviewState();
}

class _MomentsVideoPreviewState extends State<MomentsVideoPreview>
    with WidgetsBindingObserver {
  late String _scope, _authorizationScope;
  bool _foreground = true;

  bool get _authorized =>
      widget.repository.isSessionCurrent(_scope) &&
      widget.repository.authorizationScope == _authorizationScope &&
      (widget.repository.postById(widget.post.momentId)?.mediaList.any((item) =>
              item.mediaId == widget.media.mediaId &&
              item.isVideo &&
              item.isReady &&
              item.contentPath == widget.media.contentPath) ??
          false);

  void _captureScope() {
    _scope = widget.repository.sessionScope;
    _authorizationScope = widget.repository.authorizationScope;
  }

  @override
  void initState() {
    super.initState();
    _captureScope();
    widget.repository.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(MomentsVideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.media.mediaId != widget.media.mediaId ||
        oldWidget.media.contentPath != widget.media.contentPath) {
      oldWidget.repository.removeListener(_changed);
      _captureScope();
      widget.repository.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (mounted) {
      setState(() => _foreground = state == AppLifecycleState.resumed);
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (!_authorized) {
      content = MomentsStatePanel(
          icon: Icons.lock_outline,
          title: momentsText(context, zh: '内容已不可用', en: 'Content unavailable'),
          message: momentsText(context,
              zh: '查看权限或登录状态已变化', en: 'Access or account has changed.'));
    } else if (!_foreground) {
      content = const SizedBox.shrink();
    } else {
      final url = widget.repository.mediaUrl(widget.media);
      final headers = widget.repository.mediaHeaders;
      final key = ValueKey(
          'moments-video:$_scope:$_authorizationScope:${widget.media.mediaId}');
      content = switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => NativeMediaVideo(
            key: key,
            url: url,
            httpHeaders: headers,
            autoPlay: false,
            muted: false),
        _ => VideoPlayerView(
            key: key, url: url, httpHeaders: headers, autoPlay: false),
      };
    }
    return Theme(
        data: ThemeData.dark(),
        child: MomentsScaffold(
            title: momentsText(context, zh: '视频', en: 'Video'),
            body: Center(child: content)));
  }
}
