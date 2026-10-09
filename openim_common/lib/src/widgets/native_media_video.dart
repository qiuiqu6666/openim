import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import 'video_media_cache.dart';

/// Mobile playback uses platform players rather than the mpv FFI lifecycle.
class NativeMediaVideo extends StatefulWidget {
  const NativeMediaVideo(
      {super.key,
      this.file,
      this.url,
      this.path,
      this.coverUrl,
      this.httpHeaders = const {},
      required this.autoPlay,
      required this.muted,
      this.showControls = true,
      this.looping = false});
  final File? file;
  final String? url, path, coverUrl;
  final Map<String, String> httpHeaders;
  final bool autoPlay, muted;
  final bool showControls, looping;
  @override
  State<NativeMediaVideo> createState() => _NativeMediaVideoState();
}

class _NativeMediaVideoState extends State<NativeMediaVideo> {
  VideoPlayerController? _controller;
  Future<void>? _initializing;
  bool _closed = false;
  bool _failed = false;
  double? _seekSeconds;
  bool _changingSpeed = false;
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
      final cached = !local && url != null && widget.httpHeaders.isEmpty
          ? await VideoMediaCache.cachedFile(url)
          : null;
      if (_closed) return;
      final sourceFile = local ? file : cached;
      final controller = sourceFile != null
          ? VideoPlayerController.file(sourceFile)
          : VideoPlayerController.networkUrl(Uri.parse(url!),
              httpHeaders: widget.httpHeaders);
      _controller = controller;
      await controller.initialize();
      if (_closed) return;
      await controller.setVolume(widget.muted ? 0 : 1);
      if (_closed) return;
      if (widget.looping) {
        await controller.setLooping(true);
        if (_closed) return;
      }
      if (widget.autoPlay) await controller.play();
      if (mounted && !_closed) setState(() {});
      if (!local &&
          cached == null &&
          url != null &&
          widget.httpHeaders.isEmpty) {
        unawaited(Future<void>.delayed(const Duration(seconds: 2), () async {
          if (!_closed) await VideoMediaCache.remember(url);
        }));
      }
    } catch (_) {
      if (mounted && !_closed) setState(() => _failed = true);
    }
  }

  Future<void> _release() async {
    await _initializing;
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        await controller.pause();
      }
    } catch (error) {
      debugPrint('Video pause during release failed: $error');
    } finally {
      try {
        await controller.dispose();
      } catch (error) {
        debugPrint('Video release failed: $error');
      }
    }
  }

  @override
  void dispose() {
    _closed = true;
    unawaited(_release());
    super.dispose();
  }

  String _time(Duration time) =>
      '${time.inMinutes.toString().padLeft(2, '0')}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
          child: Icon(Icons.error_outline, color: Colors.white));
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      final cover = widget.coverUrl;
      return Stack(fit: StackFit.expand, children: [
        if (cover != null && cover.isNotEmpty)
          Image.network(cover,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        const Center(child: CircularProgressIndicator()),
      ]);
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
          if (widget.showControls)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.paddingOf(context).bottom + 88,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: value.isPlaying
                                ? 'videoPause'.tr
                                : 'videoPlay'.tr,
                            color: Colors.white,
                            iconSize: 44,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 48, height: 48),
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
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Transform.translate(
                                  offset: const Offset(0, 14),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${_time(Duration(milliseconds: ((_seekSeconds ?? value.position.inMilliseconds / 1000) * 1000).round()))} / ${_time(value.duration)}',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13,
                                              fontFeatures: [
                                                FontFeature.tabularFigures()
                                              ]),
                                        ),
                                      ),
                                      TextButton(
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white70,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 2),
                                          minimumSize: const Size(48, 24),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: _changingSpeed
                                            ? null
                                            : () async {
                                                const speeds = [
                                                  1.0,
                                                  1.5,
                                                  2.0,
                                                  0.5
                                                ];
                                                final index = speeds.indexOf(
                                                    controller
                                                        .value.playbackSpeed);
                                                final speed = speeds[
                                                    (index + 1) %
                                                        speeds.length];
                                                setState(() =>
                                                    _changingSpeed = true);
                                                try {
                                                  await controller
                                                      .setPlaybackSpeed(speed);
                                                } catch (_) {
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.maybeOf(
                                                            context)
                                                        ?.showSnackBar(
                                                            const SnackBar(
                                                                content: Text(
                                                                    '倍速设置失败，请重试')));
                                                  }
                                                } finally {
                                                  if (mounted) {
                                                    setState(() =>
                                                        _changingSpeed = false);
                                                  }
                                                }
                                              },
                                        child: Text(
                                            '${value.playbackSpeed.toString().replaceAll('.0', '')}×',
                                            style:
                                                const TextStyle(fontSize: 13)),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 48,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white30,
                                      thumbColor: Colors.white,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius: 4),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: 14),
                                    ),
                                    child: Slider(
                                      min: 0,
                                      max: value.duration.inMilliseconds > 0
                                          ? value.duration.inMilliseconds / 1000
                                          : 1,
                                      value: (_seekSeconds ??
                                              value.position.inMilliseconds /
                                                  1000)
                                          .clamp(
                                              0,
                                              value.duration.inMilliseconds > 0
                                                  ? value.duration
                                                          .inMilliseconds /
                                                      1000
                                                  : 1)
                                          .toDouble(),
                                      onChangeStart: (seconds) => setState(
                                          () => _seekSeconds = seconds),
                                      onChanged: (seconds) => setState(
                                          () => _seekSeconds = seconds),
                                      onChangeEnd: (seconds) async {
                                        try {
                                          await controller.seekTo(Duration(
                                              milliseconds:
                                                  (seconds * 1000).round()));
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.maybeOf(context)
                                                ?.showSnackBar(const SnackBar(
                                                    content: Text('跳转失败，请重试')));
                                          }
                                        } finally {
                                          if (mounted) {
                                            setState(() => _seekSeconds = null);
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ],
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
