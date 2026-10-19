import 'package:flutter/widgets.dart';
import 'package:media_kit_video/media_kit_video.dart' as media;
import 'package:video_player/video_player.dart';
import 'live_flv_video_controller.dart';

class LiveVideoSurface extends StatelessWidget {
  const LiveVideoSurface({super.key, required this.player});
  final VideoPlayerController player;

  @override
  Widget build(BuildContext context) {
    final current = player;
    if (current is LiveFlvVideoController) {
      final output = current.engine?.videoController;
      if (output == null) return const SizedBox.shrink();
      return media.Video(
        controller: output,
        controls: media.NoVideoControls,
        fit: BoxFit.contain,
        // Shared live owner controls pause/resume for all surfaces.
        pauseUponEnteringBackgroundMode: false,
        resumeUponEnteringForegroundMode: false,
      );
    }
    return VideoPlayer(current);
  }
}
