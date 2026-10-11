# Android decoder compatibility

Vendored from video_player_android 2.8.15, preserving upstream LICENSE and tests.
Only Android implementation is overridden; the Dart API and iOS player are unchanged.

- Both texture and platform views enable Media3 decoder initialization fallback.
- On a video decoder initialization/decoding failure, retry once with a software-only
  decoder if available. Never retry networking, audio, DRM, or unknown errors this way.
- Fallback is scoped to one player, preserving mute, play intent, media item, texture,
  and VOD position; live playback resumes at the live edge. No second player is created.
- Native log tag: ChatVideo; contains error code only, not signed stream URLs.
- Rebuild and reinstall Android after modifying this module; Dart hot reload is insufficient.

Modified upstream files: TextureVideoPlayer, PlatformViewVideoPlayer,
ExoPlayerEventListener, VideoPlayer. Added DecoderCompatibility.
