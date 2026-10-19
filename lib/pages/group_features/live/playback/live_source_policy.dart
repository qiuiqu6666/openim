import 'package:flutter/foundation.dart';
import '../models/live_models.dart';

/// Consumed locally by our AVFoundation adapter, never sent to the CDN.
Map<String, String> livePlaybackHeaders(
        {TargetPlatform? platform, bool? web}) =>
    !(web ?? kIsWeb) &&
            (platform ?? defaultTargetPlatform) == TargetPlatform.iOS
        ? const {'X-99Chat-Local-Live-Playback': '1'}
        : const {};

/// Android uses native FLV; iOS uses the live-only media_kit FLV adapter.
/// Browsers and other desktop platforms retain the backend order.
List<Uri> livePlaybackSources(LivePlayInfo info,
    {TargetPlatform? platform,
    bool? web,
    bool preferHls = const bool.fromEnvironment('LIVE_COMPARE_HLS')}) {
  final sources = info.supportedSources;
  if (preferHls) {
    bool hls(Uri uri) => uri.path.toLowerCase().endsWith('.m3u8');
    return List.unmodifiable([
      ...sources.where(hls),
      ...sources.where((uri) => !hls(uri)),
    ]);
  }
  if ((web ?? kIsWeb) ||
      !const {TargetPlatform.android, TargetPlatform.iOS}
          .contains(platform ?? defaultTargetPlatform)) {
    return sources;
  }
  bool isFlv(Uri uri) => uri.path.toLowerCase().endsWith('.flv');
  return List.unmodifiable([
    ...sources.where(isFlv),
    ...sources.where((uri) => !isFlv(uri)),
  ]);
}
