import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:openim_common/openim_common.dart';

import '../../mine/settings/widgets/settings_widgets.dart';
import 'favorite_audio_tokens.dart';

/// Plays a verified local original. The preview loader retains file ownership.
class FavoriteAudioPreview extends StatefulWidget {
  const FavoriteAudioPreview({
    super.key,
    required this.file,
    this.title,
    this.fileSizeBytes,
    this.durationHint,
  });
  final File file;
  final String? title;
  final int? fileSizeBytes;
  final Duration? durationHint;

  /// The same layout while the authenticated original is being downloaded.
  static Widget placeholder({
    String? title,
    int? fileSizeBytes,
    Duration? durationHint,
    double? progress,
    String? error,
    VoidCallback? onRetry,
  }) =>
      _FavoriteAudioLayout(
        title: title,
        fileSizeBytes: fileSizeBytes,
        duration: durationHint ?? Duration.zero,
        loading: error == null,
        progress: progress,
        error: error,
        onToggle: onRetry,
      );

  @override
  State<FavoriteAudioPreview> createState() => _FavoriteAudioPreviewState();
}

class _FavoriteAudioPreviewState extends State<FavoriteAudioPreview>
    with WidgetsBindingObserver {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false, _failed = false, _closed = false, _loading = false;
  bool _commandInFlight = false, _dragging = false, _foreground = true;
  int _intent = 0;
  double? _seekMilliseconds;
  Future<void>? _initializing;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  Future<void> _load() {
    if (_closed || _loading) return _initializing ?? Future<void>.value();
    ++_intent;
    setState(() {
      _loading = true;
      _ready = false;
      _failed = false;
      _seekMilliseconds = null;
    });
    return _initializing = _loadFile();
  }

  Future<void> _loadFile() async {
    try {
      await _player.pause();
      if (_closed) return;
      await _player.setFilePath(widget.file.path);
      if (mounted && !_closed) setState(() => _ready = true);
    } catch (_) {
      _fail(_intent);
    } finally {
      if (mounted && !_closed) setState(() => _loading = false);
    }
  }

  void _fail(int intent) {
    if (!mounted || _closed || intent != _intent) return;
    setState(() {
      _failed = true;
      _ready = false;
      _dragging = false;
      _seekMilliseconds = null;
    });
    unawaited(_player.pause().catchError((Object _) {}));
  }

  bool get _interactive =>
      _ready && !_failed && !_closed && _foreground && !_commandInFlight;

  Future<void> _toggle() async {
    if (!_interactive || _dragging) return;
    final intent = _intent;
    setState(() => _commandInFlight = true);
    try {
      if (_player.playing &&
          _player.processingState != ProcessingState.completed) {
        await _player.pause();
      } else {
        if (_player.processingState == ProcessingState.completed) {
          await _player.pause();
          if (_closed || !_foreground || intent != _intent) return;
          await _player.seek(Duration.zero);
        }
        if (!_closed && _foreground && intent == _intent) {
          // play() completes at playback end, rather than when it starts.
          unawaited(_player.play().catchError((Object _) => _fail(intent)));
          await Future<void>.value();
        }
      }
    } catch (_) {
      _fail(intent);
    } finally {
      if (mounted && !_closed) setState(() => _commandInFlight = false);
    }
  }

  Future<void> _seek(double milliseconds) async {
    if (!_interactive) return;
    final intent = _intent;
    setState(() {
      _commandInFlight = true;
      _dragging = false;
      _seekMilliseconds = milliseconds;
    });
    try {
      await _player.seek(Duration(milliseconds: milliseconds.round()));
    } catch (_) {
      _fail(intent);
    } finally {
      if (mounted && !_closed) {
        setState(() {
          _commandInFlight = false;
          _seekMilliseconds = null;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && !_closed) {
      ++_intent;
      _dragging = false;
      _seekMilliseconds = null;
      unawaited(_player.pause().catchError((Object _) {}));
    }
    if (mounted && !_closed) setState(() {});
  }

  @override
  void dispose() {
    _closed = true;
    ++_intent;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_release());
    super.dispose();
  }

  Future<void> _release() async {
    try {
      await _initializing;
    } catch (_) {}
    try {
      await _player.dispose();
    } catch (_) {
      // Native release errors must not become unhandled UI errors.
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Duration?>(
        stream: _player.durationStream,
        initialData: _player.duration,
        builder: (context, duration) => StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          initialData: _player.playerState,
          builder: (context, state) => StreamBuilder<Duration>(
            stream: _player.positionStream,
            initialData: _player.position,
            builder: (context, position) {
              final total =
                  duration.data ?? widget.durationHint ?? Duration.zero;
              final end = total.inMilliseconds
                  .toDouble()
                  .clamp(0, double.infinity)
                  .toDouble();
              final elapsed = (_seekMilliseconds ??
                      (position.data ?? Duration.zero)
                          .inMilliseconds
                          .toDouble())
                  .clamp(0, end)
                  .toDouble();
              final seekable = _interactive && end > 0;
              return _FavoriteAudioLayout(
                title: widget.title,
                fileSizeBytes: widget.fileSizeBytes,
                duration: Duration(milliseconds: end.round()),
                elapsed: Duration(milliseconds: elapsed.round()),
                loading: _loading,
                error: _failed
                    ? settingsText(context,
                        zh: '播放失败，点击重试', en: 'Could not play. Tap to retry.')
                    : null,
                playing: state.data?.playing == true &&
                    state.data?.processingState != ProcessingState.completed,
                onToggle: _loading ||
                        _closed ||
                        _commandInFlight ||
                        _dragging ||
                        !_foreground
                    ? null
                    : () => unawaited(_failed ? _load() : _toggle()),
                onSeekStart: seekable
                    ? (value) => setState(() => _dragging = true)
                    : null,
                onSeekChanged: seekable
                    ? (value) => setState(() => _seekMilliseconds = value)
                    : null,
                onSeekEnd: seekable ? (value) => unawaited(_seek(value)) : null,
              );
            },
          ),
        ),
      );
}

class _FavoriteAudioLayout extends StatelessWidget {
  const _FavoriteAudioLayout({
    this.title,
    this.fileSizeBytes,
    required this.duration,
    this.elapsed = Duration.zero,
    this.loading = false,
    this.playing = false,
    this.progress,
    this.error,
    this.onToggle,
    this.onSeekStart,
    this.onSeekChanged,
    this.onSeekEnd,
  });
  final String? title, error;
  final int? fileSizeBytes;
  final Duration duration, elapsed;
  final bool loading, playing;
  final double? progress;
  final VoidCallback? onToggle;
  final ValueChanged<double>? onSeekStart, onSeekChanged, onSeekEnd;

  String _time(Duration value) =>
      '${value.inMinutes}:${(value.inSeconds % 60).toString().padLeft(2, '0')}';

  String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final secondary = AppTokens.textSecondary(dark: dark);
    final name = title?.trim();
    final timeStyle = TextStyle(
      color: secondary,
      fontSize: FavoriteAudioTokens.captionFontSize,
      height: FavoriteAudioTokens.textHeight,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final buttonLabel = settingsText(context,
        zh: error != null ? '重试播放' : (playing ? '暂停语音' : '播放语音'),
        en: error != null
            ? 'Retry audio'
            : (playing ? 'Pause audio' : 'Play audio'));
    final end =
        duration.inMilliseconds.toDouble().clamp(0, double.infinity).toDouble();
    return Column(
      key: const ValueKey('favorite-audio-preview'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            flex: FavoriteAudioTokens.titleFlex,
            child: Text(
              name == null || name.isEmpty
                  ? settingsText(context, zh: '语音收藏', en: 'Saved audio')
                  : name,
              key: const ValueKey('favorite-audio-title'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTokens.textPrimary(dark: dark),
                fontSize: FavoriteAudioTokens.titleFontSize,
                fontWeight: FontWeight.w600,
                height: FavoriteAudioTokens.textHeight,
              ),
            ),
          ),
          if (fileSizeBytes != null && fileSizeBytes! > 0) ...[
            const SizedBox(width: AppTokens.s4),
            Flexible(
              flex: FavoriteAudioTokens.metadataFlex,
              child: Text(
                _size(fileSizeBytes!),
                key: const ValueKey('favorite-audio-size'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: timeStyle,
              ),
            ),
          ],
        ]),
        const SizedBox(height: AppTokens.s7),
        Row(children: [
          IconButton(
            key: const ValueKey('favorite-audio-play'),
            tooltip: loading
                ? settingsText(context, zh: '正在加载语音', en: 'Loading audio')
                : buttonLabel,
            onPressed: loading ? null : onToggle,
            style: IconButton.styleFrom(
              backgroundColor: AppTokens.accent,
              foregroundColor: AppTokens.onAccent,
              disabledBackgroundColor: AppTokens.accent,
              disabledForegroundColor: AppTokens.onAccent,
              fixedSize: const Size.square(FavoriteAudioTokens.playSize),
              padding: EdgeInsets.zero,
              shape: const CircleBorder(),
            ),
            icon: loading
                ? SizedBox.square(
                    dimension: FavoriteAudioTokens.loadingSize,
                    child: CircularProgressIndicator(
                      value: progress,
                      color: AppTokens.onAccent,
                      strokeWidth: FavoriteAudioTokens.loadingStroke,
                    ),
                  )
                : Icon(
                    error != null
                        ? Icons.refresh_rounded
                        : (playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded),
                    size: FavoriteAudioTokens.playIconSize,
                  ),
          ),
          const SizedBox(width: AppTokens.s5),
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                height: FavoriteAudioTokens.timelineHeight,
                child: error != null
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                          message: error!,
                          child: Text(
                            error!,
                            key: const ValueKey('favorite-audio-error'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: timeStyle,
                          ),
                        ),
                      )
                    : SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: FavoriteAudioTokens.trackHeight,
                          activeTrackColor: AppTokens.accent,
                          inactiveTrackColor: AppTokens.border(dark: dark),
                          disabledActiveTrackColor:
                              AppTokens.border(dark: dark),
                          disabledInactiveTrackColor:
                              AppTokens.border(dark: dark),
                          thumbColor: AppTokens.accent,
                          disabledThumbColor: AppTokens.border(dark: dark),
                          overlayColor: AppTokens.accent.withValues(
                              alpha: FavoriteAudioTokens.overlayOpacity),
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: FavoriteAudioTokens.thumbRadius,
                            disabledThumbRadius:
                                FavoriteAudioTokens.thumbRadius,
                          ),
                        ),
                        child: Slider(
                          key: const ValueKey('favorite-audio-seek'),
                          semanticFormatterCallback: (value) =>
                              _time(Duration(milliseconds: value.round())),
                          max: end > 0 ? end : 1,
                          value: elapsed.inMilliseconds
                              .toDouble()
                              .clamp(0, end)
                              .toDouble(),
                          onChangeStart: onSeekStart,
                          onChanged: onSeekChanged,
                          onChangeEnd: onSeekEnd,
                        ),
                      ),
              ),
              Row(children: [
                Expanded(
                  child: Text(
                    _time(elapsed),
                    key: const ValueKey('favorite-audio-elapsed'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: timeStyle,
                  ),
                ),
                Expanded(
                  child: Text(
                    _time(duration),
                    key: const ValueKey('favorite-audio-duration'),
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: timeStyle,
                  ),
                ),
              ]),
            ]),
          ),
        ]),
      ],
    );
  }
}
