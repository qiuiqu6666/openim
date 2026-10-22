import 'package:openim_common/localization.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

PopMenuInfo voiceOutputMenu() {
  final coordinator = MediaCoordinator.instance;
  final earpiece = coordinator.output.value == VoiceOutput.earpiece;
  return PopMenuInfo(
    id: 'voiceOutput',
    text: AppCopy.text(earpiece ? '扬声器播放' : '听筒播放'),
    iconWidget: Icon(
        earpiece ? Icons.volume_up_outlined : Icons.phone_in_talk_outlined,
        size: ChatMessageMenuTokens.iconSize,
        color: ChatMessageMenuTokens.foreground),
    onTap: () async {
      try {
        await coordinator
            .setOutput(earpiece ? VoiceOutput.speaker : VoiceOutput.earpiece);
      } catch (_) {
        IMViews.showToast(AppCopy.text('播放模式切换失败，请重试'));
      }
    },
  );
}
