import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:extended_image/extended_image.dart';
import 'package:openim_common/openim_common.dart';

import '../../services/moments_repository.dart';
import 'media/moments_media_gallery.dart';
import 'media/moments_video_preview.dart';
import 'moments_actions.dart';
import 'moments_widgets.dart';

/// Downloads protected media with the business token before using the shared
/// viewer. Private media never enters the shared disk network-image cache.
class MomentsMediaPreview extends StatefulWidget {
  const MomentsMediaPreview(
      {super.key,
      required this.repository,
      required this.post,
      required this.initialIndex});
  final MomentsRepository repository;
  final MomentPost post;
  final int initialIndex;
  @override
  State<MomentsMediaPreview> createState() => _MomentsMediaPreviewState();
}

class _MomentsMediaPreviewState extends State<MomentsMediaPreview> {
  late String _scope;
  late String _authorizationScope;
  int _generation = 0;
  int _currentIndex = 0;
  final Map<int, Uint8List> _bytes = {};
  final Set<int> _full = {};
  final Map<int, Future<void>> _loading = {};
  final Set<int> _thumbnailLoading = {};
  final Map<int, Object> _mediaErrors = {};
  Object? _error;
  bool _ready = false;
  bool _invalid = false;
  Object? _saveRequest;
  bool get _current =>
      widget.repository.isSessionCurrent(_scope) &&
      widget.repository.authorizationScope == _authorizationScope &&
      widget.repository.postById(widget.post.momentId) != null &&
      !_invalid;
  bool _requestCurrent(int generation) =>
      mounted && generation == _generation && _current;

  @override
  void initState() {
    super.initState();
    widget.repository.addListener(_checkPermission);
    _reset();
  }

  void _reset() {
    _generation++;
    _evict();
    _loading.clear();
    _saveRequest = null;
    _thumbnailLoading.clear();
    _scope = widget.repository.sessionScope;
    _authorizationScope = widget.repository.authorizationScope;
    _currentIndex = widget.initialIndex;
    _ready = false;
    _error = null;
    _invalid = widget.initialIndex < 0 ||
        widget.initialIndex >= widget.post.mediaList.length ||
        widget.repository.postById(widget.post.momentId) == null;
    if (!_invalid && !widget.post.mediaList[widget.initialIndex].isVideo) {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(MomentsMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameMedia =
        oldWidget.post.mediaList.length == widget.post.mediaList.length &&
            List.generate(widget.post.mediaList.length, (index) => index)
                .every((index) {
              final old = oldWidget.post.mediaList[index];
              final next = widget.post.mediaList[index];
              return old.mediaId == next.mediaId &&
                  old.contentPath == next.contentPath &&
                  old.thumbPath == next.thumbPath;
            });
    if (oldWidget.repository != widget.repository ||
        oldWidget.post.momentId != widget.post.momentId ||
        oldWidget.initialIndex != widget.initialIndex ||
        !sameMedia) {
      oldWidget.repository.removeListener(_checkPermission);
      widget.repository.addListener(_checkPermission);
      _reset();
    }
  }

  void _checkPermission() {
    if (widget.repository.isSessionCurrent(_scope) &&
        widget.repository.authorizationScope == _authorizationScope &&
        widget.repository.postById(widget.post.momentId) != null) {
      return;
    }
    if (mounted) {
      setState(() {
        _generation++;
        _invalid = true;
        _evict();
      });
    }
  }

  Future<void> _load() async {
    if (!_current) return;
    final generation = _generation;
    setState(() => _error = null);
    await _upgrade(widget.initialIndex);
    if (!_requestCurrent(generation) || !_ready) return;
    _prefetchNeighbors();
  }

  void _prefetchNeighbors() {
    // The shared viewer also prepares adjacent pages. Keep transport work to
    // those pages rather than starting eight private requests at once.
    for (final index in [_currentIndex - 1, _currentIndex + 1]) {
      if (index >= 0 && index < widget.post.mediaList.length) {
        unawaited(_loadThumbnail(index));
      }
    }
  }

  Future<void> _pageChanged(int index) async {
    if (!_current) return;
    final generation = _generation;
    _currentIndex = index;
    await _upgrade(index);
    if (_requestCurrent(generation)) _prefetchNeighbors();
  }

  Future<void> _loadThumbnail(int index) async {
    if (!_current ||
        _bytes.containsKey(index) ||
        _full.contains(index) ||
        !_thumbnailLoading.add(index)) {
      return;
    }
    final generation = _generation;
    setState(() => _mediaErrors.remove(index));
    try {
      final media = widget.post.mediaList[index];
      if (media.isVideo) throw const MomentsException('暂不支持视频预览');
      final bytes =
          await widget.repository.downloadMedia(media, thumbnail: true);
      if (!_requestCurrent(generation) ||
          _full.contains(index) ||
          (index - _currentIndex).abs() > 1) {
        return;
      }
      setState(() => _replaceBytes(index, bytes));
    } catch (error) {
      if (_requestCurrent(generation) && !_full.contains(index)) {
        setState(() => _mediaErrors[index] = error);
      }
    } finally {
      if (_requestCurrent(generation)) {
        _thumbnailLoading.remove(index);
        setState(() {});
      }
    }
  }

  Future<void> _upgrade(int index) {
    if (!_current || _full.contains(index)) return Future.value();
    return _loading[index] ??= _loadOriginal(index);
  }

  Future<void> _loadOriginal(int index) async {
    final generation = _generation;
    setState(() => _mediaErrors.remove(index));
    try {
      if (widget.post.mediaList[index].isVideo) {
        throw const MomentsException('暂不支持视频预览');
      }
      final bytes =
          await widget.repository.downloadMedia(widget.post.mediaList[index]);
      if (_requestCurrent(generation)) {
        setState(() {
          _replaceBytes(index, bytes);
          _full.add(index);
          _mediaErrors.remove(index);
          if (index == widget.initialIndex) _ready = true;
        });
      }
    } catch (error) {
      if (_requestCurrent(generation)) {
        setState(() {
          _mediaErrors[index] = error;
          if (!_ready && index == widget.initialIndex) _error = error;
        });
        if (_ready && mounted) {
          showMomentsFeedback(context, momentsErrorText(context, error));
        }
      }
    } finally {
      if (_requestCurrent(generation)) {
        _loading.remove(index);
        setState(() {});
      }
    }
  }

  bool _canSave(int generation) =>
      _requestCurrent(generation) && ModalRoute.of(context)?.isCurrent != false;

  Future<void> _showSaveMenu(int index) async {
    final generation = _generation;
    if (!_canSave(generation)) return;
    final selected = await showAppActionSheet<bool>(context,
        title: '', actions: [AppAction(StrRes.saveToAlbum, true)]);
    if (selected == true && _canSave(generation)) await _saveImage(index);
  }

  Future<void> _saveImage(int index) async {
    final generation = _generation;
    if (_saveRequest != null ||
        !_canSave(generation) ||
        index < 0 ||
        index >= widget.post.mediaList.length) {
      return;
    }
    final request = Object();
    _saveRequest = request;
    try {
      // Share the ongoing original request; never export a prefetched thumbnail.
      await _upgrade(index);
      if (!mounted || !_canSave(generation)) return;
      final bytes = _bytes[index];
      if (!_full.contains(index) || bytes == null || bytes.isEmpty) {
        IMViews.showToast(momentsText(context,
            zh: '图片加载失败，请重试后保存',
            en: 'Could not load the photo. Retry before saving.'));
        return;
      }
      final result = await saveMomentImageToGallery(bytes,
          isCurrent: () => _canSave(generation));
      if (!mounted ||
          !_canSave(generation) ||
          result == MomentsMediaSaveResult.canceled) {
        return;
      }
      IMViews.showToast(switch (result) {
        MomentsMediaSaveResult.success => StrRes.saveSuccessfully,
        MomentsMediaSaveResult.permissionDenied => momentsText(context,
            zh: '保存失败，请允许添加照片到相册',
            en: 'Allow photo access to save this photo.'),
        MomentsMediaSaveResult.unsupported => momentsText(context,
            zh: '当前平台暂不支持保存图片',
            en: 'Saving photos is not supported on this platform.'),
        _ => StrRes.saveFailed,
      });
    } finally {
      if (identical(_saveRequest, request)) _saveRequest = null;
    }
  }

  @override
  void dispose() {
    widget.repository.removeListener(_checkPermission);
    _generation++;
    _evict();
    super.dispose();
  }

  void _evict() {
    for (final bytes in _bytes.values) {
      ExtendedMemoryImageProvider(bytes).evict();
    }
    _bytes.clear();
    _full.clear();
    _mediaErrors.clear();
  }

  void _replaceBytes(int index, Uint8List bytes) {
    final previous = _bytes[index];
    if (previous != null) {
      ExtendedMemoryImageProvider(previous).evict();
    }
    _bytes[index] = bytes;
  }

  @override
  Widget build(BuildContext context) {
    if (_invalid) {
      return _pendingViewer(MomentsStatePanel(
          icon: Icons.lock_outline,
          title: momentsText(context, zh: '内容已不可用', en: 'Content unavailable'),
          message: momentsText(context,
              zh: '查看权限或登录状态已变化', en: 'Access or account has changed.')));
    }
    if (widget.post.mediaList[widget.initialIndex].isVideo) {
      return MomentsVideoPreview(
          repository: widget.repository,
          post: widget.post,
          media: widget.post.mediaList[widget.initialIndex]);
    }
    if (!_ready) {
      return _pendingViewer(_error == null
          ? const SizedBox.square(
              dimension: AppTokens.s7,
              child: CircularProgressIndicator(strokeWidth: 2))
          : MomentsStatePanel(
              icon: Icons.image_not_supported_outlined,
              title: momentsText(context,
                  zh: '图片加载失败', en: 'Could not load photos'),
              message: momentsErrorText(context, _error!),
              onAction: _load,
              actionLabel: momentsText(context, zh: '重试', en: 'Retry')));
    }
    return MediaBrowser(
        key: ValueKey(_generation),
        sources: [
          for (var i = 0; i < widget.post.mediaList.length; i++)
            MediaSource(
                thumbnail: '',
                bytes: _bytes[i],
                loading: _bytes[i] == null &&
                    (_loading.containsKey(i) || _thumbnailLoading.contains(i)),
                onRetry: _mediaErrors.containsKey(i) ? () => _upgrade(i) : null,
                tag:
                    'moments:$_scope:${widget.post.momentId}:${widget.post.mediaList[i].mediaId}',
                senderName: widget.post.author.displayName,
                sentAt:
                    DateTime.fromMillisecondsSinceEpoch(widget.post.createdAt)),
        ],
        initialIndex: widget.initialIndex,
        showGallery: false,
        onSave: (index) => unawaited(_saveImage(index)),
        onLongPress: (index) => unawaited(_showSaveMenu(index)),
        onPageChanged: _pageChanged);
  }

  Widget _pendingViewer(Widget child) {
    final viewerTheme = Theme.of(context).copyWith(
        brightness: Brightness.dark,
        colorScheme:
            ThemeData.dark().colorScheme.copyWith(primary: AppTokens.accent));
    return Theme(
        data: viewerTheme,
        child: MomentsScaffold(
          title: momentsText(context, zh: '图片', en: 'Photos'),
          fullBleed: true,
          backgroundColor: viewerTheme.colorScheme.shadow,
          body: Stack(children: [
            Center(child: child),
            Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                    bottom: false,
                    child: Row(children: [
                      SizedBox.square(
                          dimension: MomentsLayout.touchTarget,
                          child: IconButton(
                              key: const ValueKey('moments_media_back'),
                              tooltip: MaterialLocalizations.of(context)
                                  .backButtonTooltip,
                              onPressed: () => Navigator.of(context).maybePop(),
                              color: viewerTheme.colorScheme.onSurface,
                              style: IconButton.styleFrom(
                                  minimumSize: const Size.square(
                                      MomentsLayout.touchTarget),
                                  visualDensity: VisualDensity.standard),
                              icon: const Icon(
                                  Icons.arrow_back_ios_new_rounded))),
                      Text(momentsText(context, zh: '图片', en: 'Photos'),
                          style: TextStyle(
                              color: viewerTheme.colorScheme.onSurface,
                              fontSize: MomentsLayout.nameSize)),
                    ]))),
          ]),
        ));
  }
}

Future<void> openMomentsMedia(BuildContext context,
    MomentsRepository repository, MomentPost post, int index) async {
  if (index < 0 || index >= post.mediaList.length) return;
  await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => MomentsMediaPreview(
          repository: repository, post: post, initialIndex: index)));
}
