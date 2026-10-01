import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

/// Mobile playback uses platform players rather than the mpv FFI lifecycle.
class NativeMediaVideo extends StatefulWidget {
  const NativeMediaVideo(
      {super.key,
      this.file,
      this.url,
      this.path,
      required this.autoPlay,
      required this.muted});
  final File? file;
  final String? url, path;
  final bool autoPlay, muted;
  @override
  State<NativeMediaVideo> createState() => _NativeMediaVideoState();
}

class _NativeMediaVideoState extends State<NativeMediaVideo> {
  VideoPlayerController? _controller;
  Future<void>? _initializing;
  bool _closed = false;
  bool _failed = false;
  @override
  void initState() {
    super.initState();
    _initializing = _initialize();
  }

  Future<void> _initialize() async {
    try {
      final file =
          widget.file ?? (widget.path == null ? null : File(widget.path!));
      final local = file != null && await file.exists();
      if (_closed) return;
      final url = widget.url;
      if (!local && (url == null || url.isEmpty)) {
        throw StateError('Missing video');
      }
      final controller = local
          ? VideoPlayerController.file(file)
          : VideoPlayerController.networkUrl(Uri.parse(url!));
      _controller = controller;
      await controller.initialize();
      if (_closed) return;
      await controller.setVolume(widget.muted ? 0 : 1);
      if (_closed) return;
      if (widget.autoPlay) await controller.play();
      if (mounted && !_closed) setState(() {});
    } catch (_) {
      if (mounted && !_closed) setState(() => _failed = true);
    }
  }

  Future<void> _release() async {
    await _initializing;
    await _controller?.dispose();
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_release());
    super.dispose();
  }

  String _time(Duration time) =>
      '${time.inMinutes}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
          child: Icon(Icons.error_outline, color: Colors.white));
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, value, __) => Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: value.aspectRatio > 0 ? value.aspectRatio : 1,
              child: VideoPlayer(controller),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.paddingOf(context).bottom + 88,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(16),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: value.isPlaying
                              ? 'videoPause'.tr
                              : 'videoPlay'.tr,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          color: Colors.white,
                          icon: Icon(value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          onPressed: () async {
                            try {
                              if (value.isPlaying) {
                                await controller.pause();
                              } else {
                                if (value.position >= value.duration) {
                                  await controller.seekTo(Duration.zero);
                                }
                                if (!_closed) await controller.play();
                              }
                            } catch (_) {
                              if (mounted) setState(() => _failed = true);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${_time(value.position)} / ${_time(value.duration)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: VideoProgressIndicator(
                            controller,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor:
                                  Theme.of(context).colorScheme.primary,
                              bufferedColor: Colors.white54,
                              backgroundColor: Colors.white30,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
