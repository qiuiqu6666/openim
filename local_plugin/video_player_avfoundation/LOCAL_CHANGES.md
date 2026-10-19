# Local AVFoundation live playback policy

Based on video_player_avfoundation 2.8.4; upstream license retained.

The group-live iOS factory passes `X-99Chat-Local-Live-Playback: 1` as a
local creation option. The native adapter removes this marker before creating
the HTTP asset; other headers remain intact. Only opted-in items request a
2-second forward buffer and 3-second live offset, preserving the live offset
after buffering on iOS 13+. These are player preferences, not end-to-end latency
guarantees; playlist segments and network conditions still constrain playback.

Ordinary video players keep upstream defaults. No automatic stall protection
is disabled. The native regression lives in darwin/RunnerTests/VideoPlayerTests.m.
Run those tests with the plugin example's iOS Xcode test target on macOS.
