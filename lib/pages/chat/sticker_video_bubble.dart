import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  bool _visible = false;
  bool _appActive = true;
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant StickerVideoBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.clientMsgID != widget.message.clientMsgID) {
      _stop(rebuild: false);
      if (_visible) unawaited(_start());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appActive = true;
      if (_visible) {
        final controller = _controller;
        if (controller == null) {
          unawaited(_start());
        } else {
          unawaited(controller.play());
        }
      }
    } else {
      _appActive = false;
      final controller = _controller;
      if (controller != null) unawaited(controller.pause());
    }
  }

  Future<void> _start() async {
    if (!_visible ||
        !_appActive ||
        _loading ||
        _controller != null ||
        _failed) {
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
    try {
      final local = localPath != null &&
          localPath.isNotEmpty &&
          await File(localPath).exists();
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
        player = VideoPlayerController.networkUrl(Uri.parse(remoteURL!));
        await player.initialize();
      }
      if (!mounted || !_visible || !_appActive || generation != _generation) {
        return;
      }
      await player.setLooping(true);
      await player.setVolume(0);
      if (!mounted || !_visible || !_appActive || generation != _generation) {
        return;
      }
      await player.play();
      if (!mounted || !_visible || !_appActive || generation != _generation) {
        return;
      }
      setState(() => _controller = player);
      player = null; // The state now owns the controller.
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
    } finally {
      if (player != null) unawaited(player.dispose());
      _loading = false;
      if (mounted &&
          _visible &&
          _appActive &&
          _controller == null &&
          !_failed) {
        unawaited(_start());
      }
    }
  }

  void _stop({bool rebuild = true}) {
    _generation++;
    final player = _controller;
    _controller = null;
    _failed = false;
    if (player != null) unawaited(player.dispose());
    if (mounted && rebuild) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    final player = _controller;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  Widget _thumbnail() {
    final video = widget.message.videoElem;
    final path = video?.snapshotPath;
    final url = video?.snapshotUrl;
    Widget fallback() => ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: const Center(child: Icon(Icons.videocam_outlined)),
        );
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Image.file(File(path),
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback());
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(url,
          fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback());
    }
    return fallback();
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.message.videoElem;
    final width = video?.snapshotWidth ?? 0;
    final height = video?.snapshotHeight ?? 0;
    final ratio =
        width > 0 && height > 0 ? (width / height).clamp(.5, 2.0) : .75;
    final bubbleWidth = 160.w;
    final bubbleHeight = (bubbleWidth / ratio).clamp(120.h, 220.h);
    final player = _controller;
    return VisibilityDetector(
      key: ValueKey('sticker-video-${widget.message.clientMsgID}'),
      onVisibilityChanged: (visibility) {
        final visible = visibility.visibleFraction > .2;
        if (visible == _visible) return;
        _visible = visible;
        if (visible) {
          unawaited(_start());
        } else {
          _stop();
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14.r),
        child: SizedBox(
          width: bubbleWidth,
          height: bubbleHeight,
          child: Stack(fit: StackFit.expand, children: [
            if (player == null || !player.value.isInitialized)
              _thumbnail()
            else
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: player.value.size.width,
                  height: player.value.size.height,
                  child: VideoPlayer(player),
                ),
              ),
            if (player == null)
              const Center(
                  child: Icon(Icons.play_circle_fill,
                      color: Colors.white, size: 36)),
          ]),
        ),
      ),
    );
  }
}
