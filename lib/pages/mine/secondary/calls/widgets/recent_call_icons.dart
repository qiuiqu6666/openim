import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../recent_call_tokens.dart';

/// Original media glyphs from 99chat's recent_calls_page.dart.
class RecentCallMediaIcon extends StatelessWidget {
  const RecentCallMediaIcon(
      {super.key, required this.video, required this.color});

  static const audioAsset = 'lib/pages/mine/secondary/calls/assets/call.png';
  static const videoAsset = 'lib/pages/mine/secondary/calls/assets/video.webp';
  final bool video;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: RecentCallTokens.mediaIconSize,
        child: Center(
          child: Image.asset(
            video ? videoAsset : audioAsset,
            width: video
                ? RecentCallTokens.videoIconSize
                : RecentCallTokens.audioIconSize,
            height: video
                ? RecentCallTokens.videoIconSize
                : RecentCallTokens.audioIconSize,
            fit: BoxFit.contain,
            color: color,
            colorBlendMode: BlendMode.srcIn,
            gaplessPlayback: true,
            excludeFromSemantics: true,
          ),
        ),
      );
}

/// The reference's start_new_call.svg is missing in its repository. Keep its
/// 24px geometry using the original phone artwork plus the standard add glyph.
class RecentNewCallIcon extends StatelessWidget {
  const RecentNewCallIcon({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox.square(
          dimension: RecentCallTokens.newCallIconSize,
          child: Stack(children: [
            Positioned(
              left: 0,
              bottom: 0,
              child: Image.asset(
                RecentCallMediaIcon.audioAsset,
                width: RecentCallTokens.newCallPhoneSize,
                height: RecentCallTokens.newCallPhoneSize,
                color: AppTokens.accent,
                colorBlendMode: BlendMode.srcIn,
                gaplessPlayback: true,
              ),
            ),
            const Positioned(
              right: 0,
              top: 0,
              child: Icon(Icons.add_rounded,
                  size: RecentCallTokens.newCallPlusSize,
                  color: AppTokens.accent),
            ),
          ]),
        ),
      );
}
