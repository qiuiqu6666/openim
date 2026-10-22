import '../media/media_coordinator.dart';
import 'package:openim_common/localization.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import 'video_media_cache.dart';
import 'media_browser/video_hold_speed.dart';
import '../res/app_tokens.dart';
import '../utils/media/native_media_file.dart';

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

class _NativeMediaVideoState extends State<NativeMediaVideo>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  MediaLease? _lease;
  bool _requested = false;
  bool _superseded = false;
  bool _initializing = false;
  bool _skipLocal = false;
  static const _loadTimeout = Duration(seconds: 20);
  bool _closed = false;
  bool _failed = false;
  double? _seekSeconds;
  bool _changingSpeed = false;
  bool _holdingSpeed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoPlay) {
      _requested = true;
      unawaited(_initialize());
    }
  }

  // Report platform failures without leaking signed URLs, headers or paths.
  void _logFailure(String stage, Object error) {
    final raw = error is PlatformException ? error.message ?? '' : '$error';
    final detail =
        raw.replaceAll(RegExp(r'(?:https?|file)://[^\s]+'), '<source>');
    debugPrint('[ChatVideo] stage=$stage platform=${Platform.operatingSystem} '
        'type=${error.runtimeType} detail=$detail');
  }

  Future<bool> _open(VideoPlayerController controller, String source) async {
    if (_closed) return false;
    _controller = controller;
    try {
      if (!widget.muted) {
        MediaLease? ownedLease;
        final lease = ownedLease =
            await MediaCoordinator.instance.acquire(MediaKind.video, () async {
          if (ownedLease?.wasPreempted ?? true) _superseded = true;
          if (controller.value.isInitialized) {
            await controller.pause();
          } else {
            // No sound has started. Retire a pending decoder without blocking
            // the next media on a native creation Future that may arrive late.
            unawaited(controller.dispose().catchError((Object error) {
              _logFailure('retire_pending', error);
            }));
          }
        });
        if (lease == null) {
          _superseded = true;
          await controller.dispose();
          if (identical(_controller, controller)) _controller = null;
          return false;
        }
        _lease = lease;
        if (_closed || !lease.valid) {
          await lease.release();
          return false;
        }
      }
      await controller.initialize().timeout(_loadTimeout);
      if (_closed) return false;
      await controller.setVolume(widget.muted ? 0 : 1).timeout(_loadTimeout);
      if (_closed) return false;
      await controller.setLooping(widget.looping).timeout(_loadTimeout);
      if (_closed) return false;
      if (_requested && (widget.muted || _lease?.valid == true)) {
        await _play(controller).timeout(_loadTimeout);
      }
      if (_closed) return false;
      if (controller.value.hasError) {
        throw StateError(
            controller.value.errorDescription ?? 'Playback failed');
      }
      controller.addListener(_playbackChanged);
      debugPrint('[ChatVideo] stage=ready source=$source '
          'platform=${Platform.operatingSystem} '
          'size=${controller.value.size} autoPlay=${widget.autoPlay}');
      return true;
    } catch (error) {
      _logFailure(source, error);
      if (identical(_controller, controller)) {
        _controller = null;
        unawaited(_disposeController(controller));
      }
      return false;
    }
  }

  Future<void> _initialize() async {
    if (_initializing || _closed) return;
    _initializing = true;
    try {
      final file =
          widget.file ?? (widget.path == null ? null : File(widget.path!));
      final url = widget.url?.trim();
      final hasRemote = url != null && url.isNotEmpty;
      File? sourceFile;
      if (!_skipLocal) {
        try {
          final stat = await file?.stat();
          if (stat?.type == FileSystemEntityType.file && stat!.size > 0) {
            sourceFile = file;
          } else if (hasRemote && widget.httpHeaders.isEmpty) {
            sourceFile = await VideoMediaCache.cachedFile(url)
                .timeout(const Duration(seconds: 3));
          }
        } catch (error) {
          _logFailure('local_lookup', error);
        }
      }
      if (_closed) return;
      var ready = false;
      if (sourceFile != null) {
        // File-only previews (e.g. verified favorite originals) own temporary
        // files that must disappear on close; do not persist a shared copy.
        final playable = hasRemote
            ? await NativeMediaFile.prepare(sourceFile).timeout(_loadTimeout)
            : sourceFile;
        if (_closed) return;
        ready = await _open(
            VideoPlayerController.file(playable,
                videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)),
            'local');
        if (!ready) _skipLocal = true;
      }
      if (_closed) return;
      if (_superseded) {
        setState(() => _failed = !ready);
        return;
      }
      if (!ready && hasRemote) {
        ready = await _open(
            VideoPlayerController.networkUrl(Uri.parse(url),
                httpHeaders: widget.httpHeaders,
                videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)),
            'network');
      }
      if (_closed) return;
      if (_superseded) {
        setState(() => _failed = !ready);
        return;
      }
      if (!ready && hasRemote && defaultTargetPlatform == TargetPlatform.iOS) {
        final downloaded = await VideoMediaCache.downloadForPlayback(url,
                headers: widget.httpHeaders, refresh: _skipLocal)
            .timeout(_loadTimeout);
        if (_closed) return;
        ready = await _open(
            VideoPlayerController.file(downloaded,
                videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true)),
            'download');
        sourceFile = downloaded;
      }
      if (_closed) return;
      setState(() => _failed = !ready);
      // Native streaming owns playback. Do not start a second whole-file
      // download; the iOS compatibility fallback above remains available.
    } catch (error) {
      _logFailure('initialize', error);
      if (mounted && !_closed) setState(() => _failed = true);
    } finally {
      _initializing = false;
    }
  }

  Future<void> _play(VideoPlayerController controller) async {
    if (_closed) return;
    if (widget.muted) {
      await controller.play();
      return;
    }
    var lease = _lease;
    if (lease == null || !lease.valid) {
      lease = await MediaCoordinator.instance
          .acquire(MediaKind.video, controller.pause);
      if (lease == null) return;
      _lease = lease;
    }
    if (_closed) {
      await lease.release();
      return;
    }
    await lease.run(() async {
      if (!_closed) await controller.play();
    });
  }

  Future<void> _pause(VideoPlayerController controller) async {
    final lease = _lease;
    _lease = null;
    await controller.pause();
    await lease?.release(stopped: true);
  }

  void _playbackChanged() {
    final controller = _controller;
    if (controller != null && controller.value.isCompleted && _lease != null) {
      unawaited(_pause(controller));
    }
    if (_closed ||
        _failed ||
        controller == null ||
        !controller.value.hasError) {
      return;
    }
    _logFailure(
        'playback', controller.value.errorDescription ?? 'Unknown error');
    _skipLocal = true;
    controller.removeListener(_playbackChanged);
    _controller = null;
    unawaited(_disposeController(controller));
    setState(() => _failed = true);
  }

  Future<void> _disposeController(VideoPlayerController controller) async {
    controller.removeListener(_playbackChanged);
    final lease = _lease;
    _lease = null;
    try {
      await lease?.release();
      // Dispose immediately, even if initialization has not emitted an event.
      await controller.dispose();
    } catch (error) {
      _logFailure('dispose', error);
    }
  }

  void _retry() {
    if (_initializing || _closed) return;
    _superseded = false;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_disposeController(controller));
    setState(() => _failed = false);
    _holdingSpeed = false;
    unawaited(_initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      final controller = _controller;
      if (controller != null) {
        unawaited(_pause(controller).catchError((Object error) {
          _logFailure('background_pause', error);
        }));
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _closed = true;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_disposeController(controller));
    super.dispose();
  }

  String _time(Duration time) =>
      '${time.inMinutes.toString().padLeft(2, '0')}:${(time.inSeconds % 60).toString().padLeft(2, '0')}';
  @override
  Widget build(BuildContext context) {
    if (!_requested) {
      return Stack(fit: StackFit.expand, children: [
        if (widget.coverUrl?.isNotEmpty == true)
          Image.network(widget.coverUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        Center(
            child: IconButton(
          tooltip: 'videoPlay'.tr,
          icon: const Icon(Icons.play_arrow_rounded),
          onPressed: () {
            setState(() => _requested = true);
            unawaited(_initialize());
          },
        )),
      ]);
    }
    if (_failed) {
      return Center(
        child: TextButton.icon(
          onPressed: _retry,
          icon: const Icon(Icons.refresh),
          label: Text(AppCopy.text('视频加载失败，点击重试')),
        ),
      );
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
            Positioned.fill(
              child: VideoHoldSpeed(
                key: ObjectKey(controller),
                controller: controller,
                blocked: _changingSpeed || _seekSeconds != null,
                onBusyChanged: (busy) {
                  if (mounted) setState(() => _holdingSpeed = busy);
                },
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
                                  await _pause(controller);
                                } else {
                                  if (value.position >= value.duration) {
                                    await controller.seekTo(Duration.zero);
                                  }
                                  if (!_closed) await _play(controller);
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
                                Row(
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
                                        padding: AppTokens.videoSpeedPadding,
                                        alignment: Alignment.bottomCenter,
                                        minimumSize:
                                            AppTokens.videoSpeedMinimumSize,
                                        visualDensity: VisualDensity.standard,
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: _changingSpeed || _holdingSpeed
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
                                                  (index + 1) % speeds.length];
                                              setState(
                                                  () => _changingSpeed = true);
                                              try {
                                                await controller
                                                    .setPlaybackSpeed(speed);
                                              } catch (_) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.maybeOf(
                                                          context)
                                                      ?.showSnackBar(SnackBar(
                                                          content: Text(
                                                              AppCopy.text(
                                                                  '倍速设置失败，请重试'))));
                                                }
                                              } finally {
                                                if (mounted) {
                                                  setState(() =>
                                                      _changingSpeed = false);
                                                }
                                              }
                                            },
                                      child: Text(
                                          '${value.playbackSpeed.toStringAsFixed(1)}倍',
                                          style: AppTokens.videoSpeedTextStyle),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  height: AppTokens.videoSeekTouchHeight,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight:
                                          AppTokens.videoSeekTrackHeight,
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white30,
                                      thumbColor: Colors.white,
                                      thumbShape: const RoundSliderThumbShape(
                                          enabledThumbRadius:
                                              AppTokens.videoSeekThumbRadius),
                                      overlayShape:
                                          const RoundSliderOverlayShape(
                                              overlayRadius: AppTokens
                                                  .videoSeekOverlayRadius),
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
                                                ?.showSnackBar(SnackBar(
                                                    content: Text(AppCopy.text(
                                                        '跳转失败，请重试'))));
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
