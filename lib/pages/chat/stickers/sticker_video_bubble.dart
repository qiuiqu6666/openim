import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'sticker_video_playback_pool.dart';

/// Only video messages marked as personal stickers use this inline player.
class StickerVideoBubble extends StatefulWidget {
  const StickerVideoBubble({super.key, required this.message});

  final Message message;

  @override
  State<StickerVideoBubble> createState() => _StickerVideoBubbleState();
}

class _StickerVideoBubbleState extends State<StickerVideoBubble>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  StickerVideoLease? _lease;
  bool _visible = false;
  bool _appActive = true;
  bool _routeActive = true;
  bool _loading = false;
  bool _failed = false;
  bool _previewing = false;
  int _generation = 0;
  String? _thumbnailPath;
  bool _thumbnailExists = false;
  bool _thumbnailPending = false;
  int _thumbnailGeneration = 0;
  (String?, String?, String?)? _videoSource;

  (String?, String?, String?) get _currentVideoSource => (
        widget.message.clientMsgID,
        widget.message.videoElem?.videoPath,
        widget.message.videoElem?.videoUrl,
      );

  bool get _canPlay =>
      mounted && _visible && _appActive && _routeActive && !_previewing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _appActive = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    _videoSource = _currentVideoSource;
    _updateThumbnail();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active =
        (ModalRoute.isCurrentOf(context) ?? true) && TickerMode.of(context);
    if (active == _routeActive) return;
    _routeActive = active;
    if (active) {
      unawaited(_start());
    } else {
      _stop(rebuild: false);
    }
  }

  @override
  void didUpdateWidget(covariant StickerVideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateThumbnail();
    final source = _currentVideoSource;
    if (source != _videoSource) {
      _videoSource = source;
      _stop(rebuild: false);
      if (_canPlay) unawaited(_start());
    }
  }

  void _updateThumbnail() {
    final path = widget.message.videoElem?.snapshotPath;
    if (path == _thumbnailPath) return;
    _thumbnailPath = path;
    _thumbnailExists = false;
    _thumbnailPending = path != null && path.isNotEmpty;
    final generation = ++_thumbnailGeneration;
    if (path == null || path.isEmpty) return;
    unawaited(_checkThumbnail(path, generation));
  }

  Future<void> _checkThumbnail(String path, int generation) async {
    var exists = false;
    try {
      exists = await File(path).exists();
    } on FileSystemException {
      // Keep the remote thumbnail available if the local file cannot be read.
    }
    if (!mounted || generation != _thumbnailGeneration) return;
    setState(() {
      _thumbnailExists = exists;
      _thumbnailPending = false;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appActive = true;
      if (_canPlay) {
        final controller = _controller;
        if (controller == null) {
          unawaited(_start());
        } else {
          unawaited(controller.play());
        }
      }
    } else {
      _appActive = false;
      _stop();
    }
  }

  Future<void> _start() async {
    if (!_canPlay || _loading || _controller != null || _failed) {
      return;
    }
    final video = widget.message.videoElem;
    final localPath = video?.videoPath;
    final remoteURL = video?.videoUrl;
    if ((localPath == null || localPath.isEmpty) &&
        (remoteURL == null || remoteURL.isEmpty)) {
      return;
    }
    _loading = true;
    final generation = ++_generation;
    VideoPlayerController? player;
    StickerVideoLease? lease;
    try {
      // Ignore brief appearances while flinging through the timeline.
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!_canPlay || generation != _generation) return;
      lease = await StickerVideoPlaybackPool.shared.acquire(this);
      if (lease == null || !_canPlay || generation != _generation) return;
      final local = localPath != null &&
          localPath.isNotEmpty &&
          await File(localPath).exists();
      if (!_canPlay || generation != _generation) return;
      if (local) {
        player = VideoPlayerController.file(File(localPath));
        try {
          await player.initialize();
        } catch (_) {
          await player.dispose();
          player = null;
          if (remoteURL == null || remoteURL.isEmpty) rethrow;
        }
      }
      if (player == null) {
        if (!_canPlay || generation != _generation) return;
        player = VideoPlayerController.networkUrl(Uri.parse(remoteURL!));
        await player.initialize();
      }
      if (!_canPlay || generation != _generation) {
        return;
      }
      await player.setLooping(true);
      await player.setVolume(0);
      if (!_canPlay || generation != _generation) {
        return;
      }
      await player.play();
      if (!_canPlay || generation != _generation) {
        return;
      }
      setState(() => _controller = player);
      _lease = lease;
      lease = null;
      player = null; // The state now owns the controller.
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    } finally {
      await _disposePlayer(player, lease);
      _loading = false;
      if (_canPlay && _controller == null && !_failed) {
        unawaited(_start());
      }
    }
  }

  void _stop({bool rebuild = true}) {
    _generation++;
    StickerVideoPlaybackPool.shared.cancel(this);
    final player = _controller;
    final lease = _lease;
    _lease = null;
    _controller = null;
    _failed = false;
    unawaited(_disposePlayer(player, lease));
    if (mounted && rebuild) setState(() {});
  }

  Future<void> _disposePlayer(
      VideoPlayerController? player, StickerVideoLease? lease) async {
    try {
      await player?.dispose();
    } catch (_) {
      // Teardown must still release the budget and unblock waiting rows.
    } finally {
      lease?.release();
    }
  }

  Future<void> _openPreview() async {
    if (_previewing || widget.message.hasExpired) return;
    final video = widget.message.videoElem;
    final path = video?.videoPath;
    final url = video?.videoUrl;
    if ((path == null || path.isEmpty) && (url == null || url.isEmpty)) return;
    _previewing = true;
    _stop();
    try {
      await showStickerPreview(
        context,
        MediaSource(
          url: url,
          thumbnail: video?.snapshotUrl ?? '',
          file: path == null || path.isEmpty ? null : File(path),
          tag: widget.message.clientMsgID,
          isVideo: true,
        ),
      );
    } finally {
      _previewing = false;
      if (mounted) unawaited(_start());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _visible = false;
    _stop(rebuild: false);
    super.dispose();
  }

  Widget _thumbnail(double width, double height, BoxFit fit) {
    final video = widget.message.videoElem;
    final url = video?.snapshotUrl;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = ImageUtil.decodeDimension(width, pixelRatio);
    final cacheHeight = ImageUtil.decodeDimension(height, pixelRatio);
    Widget fallback() => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: const Center(child: Icon(Icons.videocam_outlined)),
        );
    Widget remote() => url != null && url.isNotEmpty
        ? ImageUtil.networkImage(
            url: url,
            width: width,
            height: height,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            resizePolicy: ResizeImagePolicy.fit,
            cacheRawData: false,
            fit: fit,
            errorWidget: fallback(),
          )
        : fallback();
    if (_thumbnailExists && _thumbnailPath != null) {
      return ImageUtil.fileImage(
        file: File(_thumbnailPath!),
        width: width,
        height: height,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        resizePolicy: ResizeImagePolicy.fit,
        cacheRawData: false,
        fit: fit,
        errorWidget: remote(),
      );
    }
    return _thumbnailPending ? fallback() : remote();
  }

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final video = widget.message.videoElem;
        final width = video?.snapshotWidth ?? 0;
        final height = video?.snapshotHeight ?? 0;
        final player = _controller;
        final source = width > 0 && height > 0
            ? Size(width.toDouble(), height.toDouble())
            : player?.value.size;
        final size = StickerBubbleLayout.imageSize(source ?? Size.zero,
            screenSize: MediaQuery.sizeOf(context),
            availableWidth: constraints.maxWidth,
            availableHeight: constraints.maxHeight,
            isDesktop: StickerBubbleLayout.usesDesktopLimits);
        final fit = StickerBubbleLayout.imageFit(source, size);
        return VisibilityDetector(
          key: ValueKey('sticker-video-${widget.message.clientMsgID}'),
          onVisibilityChanged: (visibility) {
            if (!mounted) return;
            // Hysteresis avoids repeatedly recreating a player at one edge.
            final visible = visibility.visibleFraction >= (_visible ? .3 : .5);
            if (visible == _visible) return;
            _visible = visible;
            if (visible) {
              unawaited(_start());
            } else {
              _stop();
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openPreview,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(StickerBubbleLayout.radius),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(fit: StackFit.expand, children: [
                  if (player == null || !player.value.isInitialized)
                    _thumbnail(size.width, size.height, fit)
                  else
                    FittedBox(
                      fit: fit,
                      child: SizedBox(
                        width: player.value.size.width,
                        height: player.value.size.height,
                        child: VideoPlayer(player),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        );
      });
}
