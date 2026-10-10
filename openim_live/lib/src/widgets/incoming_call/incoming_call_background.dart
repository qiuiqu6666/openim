import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../call_surface/call_full_screen_surface.dart';
import 'incoming_call_tokens.dart';

/// Decodes the full-bleed face after the entry fade, at the same bounded size
/// as 99chat. This is an image plus a scrim, not a per-frame blur filter.
class IncomingCallBackground extends StatefulWidget {
  const IncomingCallBackground(
      {super.key, this.faceURL, required this.isVideo});

  final String? faceURL;
  final bool isVideo;

  @override
  State<IncomingCallBackground> createState() => _IncomingCallBackgroundState();
}

class _IncomingCallBackgroundState extends State<IncomingCallBackground> {
  Timer? _timer;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(
      widget.isVideo
          ? IncomingCallTokens.videoBackdropDelay
          : IncomingCallTokens.audioBackdropDelay,
      () {
        if (mounted) setState(() => _ready = true);
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final face = widget.faceURL?.trim() ?? '';
    final cacheSize =
        (MediaQuery.sizeOf(context).shortestSide * .5).round().clamp(360, 720);
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Stack(fit: StackFit.expand, children: [
          const ColoredBox(color: CallSurfaceTokens.background),
          if (_ready && IMUtils.isUrlValid(face))
            ImageUtil.networkImage(
              url: face,
              fit: BoxFit.cover,
              cacheWidth: cacheSize,
              cacheHeight: cacheSize,
              cacheRawData: false,
              resizePolicy: ResizeImagePolicy.fit,
              loadProgress: false,
              loadingWidget: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
            ),
          ColoredBox(color: IncomingCallTokens.backdropScrim),
        ]),
      ),
    );
  }
}
