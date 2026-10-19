import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';
import 'live_flv_video_controller.dart';
import 'live_source_policy.dart';

VideoPlayerController createLiveVideo(Uri source,
    {TargetPlatform? platform, bool? web}) {
  final nativeIOS = !(web ?? kIsWeb) &&
      (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;
  if (nativeIOS && source.path.toLowerCase().endsWith('.flv')) {
    return LiveFlvVideoController(source);
  }
  return VideoPlayerController.networkUrl(source,
      httpHeaders: livePlaybackHeaders(platform: platform, web: web));
}
