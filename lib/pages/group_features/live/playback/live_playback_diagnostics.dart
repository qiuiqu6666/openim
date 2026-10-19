import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Opt-in, local diagnostics. Buffer ahead is NOT end-to-end live latency.
class LivePlaybackDiagnostics {
  LivePlaybackDiagnostics({
    this.enabled = const bool.fromEnvironment('LIVE_PLAYBACK_DIAGNOSTICS'),
    void Function(String)? sink,
    Duration Function()? elapsed,
  })  : _sink = sink ?? debugPrint,
        _elapsed = elapsed ?? (Stopwatch()..start()).elapsedDuration;

  final bool enabled;
  final void Function(String) _sink;
  final Duration Function() _elapsed;
  Duration? _lastSample;
  Duration _openedAt = Duration.zero;
  String _protocol = 'unknown';

  void opened(Uri source) {
    _protocol = source.path.toLowerCase().endsWith('.flv')
        ? 'flv'
        : source.path.toLowerCase().endsWith('.m3u8')
            ? 'hls'
            : 'http';
    _openedAt = _elapsed();
    _lastSample = null;
    event('open');
  }

  void event(String event, [VideoPlayerValue? value]) {
    if (!enabled) return;
    final now = _elapsed();
    if (event == 'sample' &&
        _lastSample != null &&
        now - _lastSample! < const Duration(seconds: 5)) {
      return;
    }
    if (event == 'sample') _lastSample = now;
    var ahead = Duration.zero;
    if (value != null) {
      for (final range in value.buffered) {
        if (range.start <= value.position &&
            range.end >= value.position &&
            range.end - value.position > ahead) {
          ahead = range.end - value.position;
        }
      }
    }
    _sink('[LivePlayback] ${jsonEncode({
          'event': event,
          'protocol': _protocol,
          'sinceOpenMs': (now - _openedAt).inMilliseconds,
          if (value != null) ...{
            'positionMs': value.position.inMilliseconds,
            'bufferAheadMs': ahead.inMilliseconds,
            'buffering': value.isBuffering,
            'playing': value.isPlaying,
          },
        })}');
  }
}

extension on Stopwatch {
  Duration elapsedDuration() => elapsed;
}
