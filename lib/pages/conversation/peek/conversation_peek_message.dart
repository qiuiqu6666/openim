import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat/messages/custom/chat_custom_message.dart';
import '../../chat/media/widgets/chat_video_thumbnail.dart';
import '../../fund/notifications/fund_claim_notice.dart';
import 'conversation_peek_loader.dart';

/// Compact, non-interactive adaptation of the existing chat message renderer.
/// Layout follows 99chat conversation_peek_message_item.dart at d7c3c65.
class ConversationPeekMessage extends StatelessWidget {
  const ConversationPeekMessage({
    super.key,
    required this.message,
    required this.isGroupChat,
    this.peerName = '',
  });

  final Message message;
  final bool isGroupChat;
  final String peerName;

  static const avatarSize = 40.0;
  static const messageSpacing = 3.0;
  static const mediaMaxWidth = 220.0;
  static const mediaMaxHeight = 260.0;

  /// A preview must not expose burn content, including a quoted/merged copy.
  static bool containsPrivateContent(Message message, [int depth = 0]) {
    return ConversationPeekLoader.containsPrivateContent(message, depth);
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    if (containsPrivateContent(message)) {
      return _systemText(context,
          zh ? '私密消息请进入会话查看' : 'Open the chat to view private messages');
    }
    final notice = FundClaimNotice.parse(message);
    if (notice != null) {
      return _systemText(
          context, notice.text(message, OpenIM.iMManager.userID));
    }
    return IgnorePointer(
      child: ChatItemView(
        message: message,
        itemMargin: const EdgeInsets.symmetric(vertical: messageSpacing),
        itemPadding: EdgeInsets.zero,
        avatarSize: avatarSize,
        ignorePointer: true,
        textScaleFactor: DataSp.getChatFontSizeFactor(),
        showLeftNickname: isGroupChat,
        showRightNickname: false,
        // The preview has no outgoing avatar/name. Avoid depending on a full
        // profile snapshot while the SDK is restoring the account session.
        rightNickname: '',
        rightFaceUrl: '',
        onTapUserProfile: (_) {},
        mediaItemBuilder: _media,
        customTypeBuilder: (context, item) => buildChatCustomMessage(
          context,
          item,
          isGroupChat: isGroupChat,
          peerName: peerName,
          textScaleFactor: DataSp.getChatFontSizeFactor(),
        ),
      ),
    );
  }

  Widget _systemText(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );

  Widget? _media(BuildContext context, Message item) {
    final outgoing = item.sendID == OpenIM.iMManager.userID;
    if (item.isPictureType) {
      return ChatPictureView(
        message: item,
        isISend: outgoing,
        maxDisplayWidth: mediaMaxWidth,
        maxDisplayHeight: mediaMaxHeight,
      );
    }
    if (!item.isVideoType) return null;
    final video = item.videoElem;
    final width = video?.snapshotWidth ?? 0;
    final height = video?.snapshotHeight ?? 0;
    final ratio = width > 0 && height > 0 ? width / height : 1.0;
    final displayWidth = (mediaMaxHeight * ratio).clamp(1.0, mediaMaxWidth);
    final displayHeight = (displayWidth / ratio).clamp(1.0, mediaMaxHeight);
    return SizedBox(
      width: displayWidth,
      height: displayHeight,
      child: Stack(fit: StackFit.expand, children: [
        ChatVideoThumbnail(
          path: video?.snapshotPath,
          url: video?.snapshotUrl,
          width: displayWidth,
        ),
        const Center(
            child: Icon(Icons.play_circle_fill,
                color: AppTokens.onAccent, size: 36)),
      ]),
    );
  }
}
