import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Do not even construct a player until playback was explicitly requested.
class OnDemandVideo extends StatefulWidget {
  const OnDemandVideo(
      {super.key,
      required this.autoPlay,
      required this.poster,
      required this.player});
  final bool autoPlay;
  final Widget poster;
  final WidgetBuilder player;

  @override
  State<OnDemandVideo> createState() => _OnDemandVideoState();
}

class _OnDemandVideoState extends State<OnDemandVideo> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    if (_started || widget.autoPlay) return widget.player(context);
    return Stack(fit: StackFit.expand, children: [
      widget.poster,
      Center(
          child: IconButton.filled(
        tooltip: 'mediaPlayVideo'.tr,
        onPressed: () => setState(() => _started = true),
        icon: const Icon(Icons.play_arrow),
      )),
    ]);
  }
}
