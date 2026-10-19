import 'package:flutter/foundation.dart';
import '../models/live_models.dart';

/// Consumed locally by our AVFoundation adapter, never sent to the CDN.
Map<String, String> livePlaybackHeaders(
        {TargetPlatform? platform, bool? web}) =>
    !(web ?? kIsWeb) &&
            (platform ?? defaultTargetPlatform) == TargetPlatform.iOS
        ? const {'X-99Chat-Local-Live-Playback': '1'}
        : const {};

/// Android's native player supports HTTP FLV. Keep other platforms on the
/// backend order until their player supports the same format.
List<Uri> livePlaybackSources(LivePlayInfo info,
    {TargetPlatform? platform, bool? web}) {
  final sources = info.supportedSources;
  if ((web ?? kIsWeb) ||
      (platform ?? defaultTargetPlatform) != TargetPlatform.android) {
    return sources;
  }
  bool isFlv(Uri uri) => uri.path.toLowerCase().endsWith('.flv');
  return List.unmodifiable([
    ...sources.where(isFlv),
    ...sources.where((uri) => !isFlv(uri)),
  ]);
}
