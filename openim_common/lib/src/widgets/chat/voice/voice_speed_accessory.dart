import 'package:flutter/material.dart';
import 'package:openim_common/localization.dart';
import 'package:openim_common/openim_common.dart';
import '../../../res/chat_voice_tokens.dart';

/// A sibling of the complete bubble, including its footer and menu anchor.
class VoiceSpeedAccessory extends StatelessWidget {
  const VoiceSpeedAccessory(
      {super.key,
      required this.playback,
      required this.messageID,
      required this.outgoing,
      required this.child});

  final VoicePlaybackController playback;
  final String messageID;
  final bool outgoing;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: playback,
        child: child,
        builder: (context, bubble) {
          final showAction =
              (playback.playing || playback.paused || playback.loading) &&
                  playback.current?.clientMsgID == messageID;
          final label = playback.paused
              ? '继续播放'
              : playback.speed == 1.0
                  ? '倍速播放'
                  : '原速播放';
          final colors = Theme.of(context).colorScheme;
          final button = TextButton(
            key: const ValueKey('voice-playback-speed'),
            style: TextButton.styleFrom(
              minimumSize: const Size.square(kMinInteractiveDimension),
              padding: EdgeInsets.zero,
              foregroundColor: colors.onSurfaceVariant,
              overlayColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              shape: const StadiumBorder(),
            ),
            onPressed: playback.loading
                ? null
                : () async {
                    try {
                      if (playback.paused) {
                        await playback.toggle(playback.current!);
                      } else {
                        await playback.cycleSpeed();
                      }
                    } catch (_) {
                      IMViews.showToast(AppCopy.text('语音播放操作失败，请重试'));
                    }
                  },
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: colors.surfaceContainerHighest,
                shape: const StadiumBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: ChatVoiceTokens.playbackActionHorizontalPadding,
                  vertical: ChatVoiceTokens.playbackActionVerticalPadding,
                ),
                child: Text(AppCopy.text(label),
                    style: const TextStyle(
                      fontSize: ChatVoiceTokens.playbackActionFontSize,
                      height: ChatVoiceTokens.controlLineHeight,
                      fontWeight: FontWeight.normal,
                    )),
              ),
            ),
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (outgoing)
                showAction
                    ? Padding(
                        padding: const EdgeInsets.only(right: AppTokens.s3),
                        child: button)
                    : const SizedBox.shrink(),
              Flexible(child: bubble!),
              if (!outgoing)
                showAction
                    ? Padding(
                        padding: const EdgeInsets.only(left: AppTokens.s3),
                        child: button)
                    : const SizedBox.shrink(),
            ],
          );
        },
      );
}
