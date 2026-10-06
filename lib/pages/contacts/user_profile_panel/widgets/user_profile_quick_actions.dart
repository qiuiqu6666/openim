import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../user_profile_tokens.dart';

/// Equal-height quick actions; callbacks stay owned by the OpenIM controller.
class UserProfileQuickActions extends StatelessWidget {
  const UserProfileQuickActions({
    super.key,
    required this.voiceLabel,
    required this.videoLabel,
    required this.messageLabel,
    required this.onVoice,
    required this.onVideo,
    required this.onMessage,
  });
  final String voiceLabel, videoLabel, messageLabel;
  final VoidCallback onVoice, onVideo, onMessage;

  @override
  Widget build(BuildContext context) => Padding(
        padding: UserProfileTokens.actionPadding,
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _action(context, 'user_profile_voice', voiceLabel,
                Icons.call_rounded, onVoice),
            const SizedBox(width: AppTokens.s3),
            _action(context, 'user_profile_video', videoLabel,
                Icons.videocam_rounded, onVideo),
            const SizedBox(width: AppTokens.s3),
            _action(context, 'user_profile_message', messageLabel,
                Icons.chat_bubble_rounded, onMessage,
                primary: true),
          ]),
        ),
      );

  Widget _action(BuildContext context, String id, String label, IconData icon,
      VoidCallback onTap,
      {bool primary = false}) {
    final text = primary ? AppTokens.onAccent : UserProfileTokens.text(context);
    return Expanded(
      child: Material(
        key: ValueKey(id),
        color: primary
            ? UserProfileTokens.primaryAction
            : UserProfileTokens.card(context),
        borderRadius: BorderRadius.circular(AppTokens.rLg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.rLg),
          child: Padding(
            padding: UserProfileTokens.actionContentPadding,
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon,
                      size: UserProfileTokens.actionIconSize, color: text),
                  const SizedBox(height: UserProfileTokens.actionGap),
                  Text(label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: AppTokens.captionFontSize,
                          height: 1.3,
                          color: text)),
                ]),
          ),
        ),
      ),
    );
  }
}
