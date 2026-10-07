import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:openim_common/openim_common.dart';

import '../../chat_logic.dart';
import '../selection/message_selection_controller.dart';
import '../custom/chat_custom_message.dart';
import '../../../fund/notifications/fund_claim_notice.dart';
import '../../composer/mention_id.dart';
import '../../fund/fund_message_card.dart';
import '../../group/announcements/announcement_mention_link.dart';
import '../../media/chat_picture_gallery.dart';
import '../../media/chat_media_message_locator.dart';
import '../../media/widgets/chat_video_thumbnail.dart';
import '../../stickers/sticker_video_bubble.dart';
import '../../stickers/sticker_video_message.dart';
import '../../../group_features/sangong/widgets/sangong_message_actions.dart';

/// Renders one message and delegates actions to the route's public facade.
class ChatMessageTile extends StatelessWidget {
  const ChatMessageTile(
      {super.key,
      required this.logic,
      required this.message,
      this.leftAvatar,
      this.textContentBuilder,
      this.customTypeBuilder,
      this.copyText});

  final ChatLogic logic;
  final Message message;
  final Widget? leftAvatar;
  final ItemViewBuilder? textContentBuilder;
  final CustomTypeBuilder? customTypeBuilder;
  final String? copyText;

  @override
  Widget build(BuildContext context) {
    final notice = FundClaimNotice.parse(message);
    if (notice != null) {
      return Obx(() {
        final duplicates = logic.messageList
            .where((item) => FundClaimNotice.parse(item)?.key == notice.key);
        if (duplicates.isNotEmpty &&
            duplicates.first.clientMsgID != message.clientMsgID) {
          return const SizedBox.shrink();
        }
        return Center(
          child: Text(notice.text(message, OpenIM.iMManager.userID),
              textAlign: TextAlign.center,
              style: Styles.ts_8E9AB0_12sp.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        );
      });
    }
    return message.isVoiceType
        ? ListenableBuilder(
            listenable: logic.voiceTranscriptions,
            builder: (_, child) => Obx(() => _buildItemView(context, message)),
          )
        : Obx(() => _buildItemView(context, message));
  }

  Widget _buildItemView(BuildContext context, Message message) => ChatItemView(
        key: logic.itemKey(message),
        message: message,
        isStickerMedia: isStickerVideoMessage(message),
        textScaleFactor: logic.scaleFactor.value,
        allAtMap: logic.getAtMapping(message),
        timelineStr: logic.isOfficialNotificationChat &&
                logic.getShowTime(message) != null
            ? formatChatMessageTime(context, message.sendTime!)
            : logic.getShowTime(message),
        onTapTimeline: () => logic.onTapTimeline(context, message),
        timelineSemanticLabel: 'chatJumpToDate'.tr,
        sendStatusSubject: logic.sendStatusSub,
        leftNickname: logic.getNewestNickname(message),
        leftFaceUrl: logic.isOfficialNotificationChat &&
                message.sendID == logic.userID &&
                (logic.getNewestFaceURL(message)?.isEmpty ?? true)
            ? logic.faceUrl.value
            : logic.getNewestFaceURL(message),
        leftAvatar: leftAvatar,
        textContentBuilder: textContentBuilder,
        rightNickname: logic.senderName,
        rightFaceUrl: OpenIM.iMManager.userInfo.faceURL,
        showLeftNickname: !logic.isSingleChat,
        showRightNickname: false,
        onFailedToResend: logic.isOfficialNotificationChat
            ? null
            : () => logic.failedResend(message),
        onClickItemView: logic.isOfficialNotificationChat
            ? null
            : () => logic.parseClickEvent(message),
        onVoicePlayed: () => logic.markVoicePlayed(message),
        voicePlayback: logic.voicePlayback,
        voiceTranscription: logic.displayedVoiceTranscription(message),
        onToggleVoiceTranscription: () =>
            logic.voiceTranscriptions.toggle(message),
        onRetryVoiceTranscription: () => logic.transcribeVoice(message),
        messageMenus: [
          ...SangongMessageActions.items(context, message),
          if (logic.canAddMessageToStickers(message))
            PopMenuInfo(
              id: 'add_to_stickers',
              text: StrRes.addToStickers,
              onTap: () => logic.addMessageToStickers(message),
            ),
          if (!logic.isOfficialNotificationChat &&
              logic.canTranscribeVoice(message) &&
              !logic.voiceTranscriptions.stateFor(message).loading &&
              !logic.voiceTranscriptions.stateFor(message).hasText)
            PopMenuInfo(
              id: 'voiceToText',
              text: 'voiceToText'.tr,
              onTap: () => logic.transcribeVoice(message),
            ),
          if (message.attachedInfoElem?.isPrivateChat != true &&
              [
                MessageType.text,
                MessageType.atText,
                MessageType.advancedText,
                MessageType.quote
              ].contains(message.contentType))
            PopMenuInfo(
              id: 'copyMessage',
              text: StrRes.copy,
              onTap: () => IMUtils.copy(
                text: copyText ??
                    logic.copyTextMap[message.clientMsgID] ??
                    IMUtils.parseMsg(message),
              ),
            ),
          if (logic.canForward(message))
            PopMenuInfo(
              id: 'replyMessage',
              text: StrRes.menuReply,
              onTap: () => logic.replyToMessage(message),
            ),
          if (logic.canForward(message))
            PopMenuInfo(
              id: 'forwardMessage',
              text: StrRes.menuForward,
              onTap: () => logic.forwardMessage(message),
            ),
          if (logic.canFavorite(message))
            PopMenuInfo(
              id: 'favorite_message',
              text: StrRes.favoriteCollection,
              onTap: () => logic.favoriteMessage(message),
            ),
          if (logic.canRevoke(message))
            PopMenuInfo(
              id: 'revoke',
              text: StrRes.menuRevoke,
              onTap: () => logic.revokeMessage(message),
            ),
          if (!logic.isOfficialNotificationChat)
            PopMenuInfo(
              id: 'delete',
              text: StrRes.delete,
              onTap: () => logic.deleteMessage(message),
            ),
          if (!logic.isOfficialNotificationChat &&
              MessageSelectionController.canSelect(message))
            PopMenuInfo(
              id: 'multiSelect',
              text: 'chatSelectionEnter'.tr,
              onTap: () => logic.messageSelection.enter(message),
            ),
        ],
        visibilityChange: (msg, visible) {
          logic.setFundMessageVisible(message, visible);
        },
        onLongPressRightAvatar: logic.isOfficialNotificationChat ? null : () {},
        onLongPressLeftAvatar: logic.isGroupChat
            ? () => logic.onLongPressAvatar(context, message)
            : null,
        onTapLeftAvatar: logic.isOfficialNotificationChat
            ? null
            : () => logic.onTapLeftAvatar(message),
        onTapRightAvatar:
            logic.isOfficialNotificationChat ? null : logic.onTapRightAvatar,
        onVisibleTrulyText: (text) {
          logic.copyTextMap[message.clientMsgID] = text;
        },
        customTypeBuilder: (context, message) =>
            customTypeBuilder?.call(context, message) ??
            _buildCustomTypeItemView(context, message),
        patterns: <MatchPattern>[
          ..._mentionPatterns(message),
          MatchPattern(
            type: PatternType.custom,
            pattern: mentionIDPattern,
            onTap: (value, _) => logic.searchMentionID(value),
          ),
          MatchPattern(
            type: PatternType.email,
            onTap: logic.clickLinkText,
          ),
          MatchPattern(
            type: PatternType.url,
            onTap: logic.clickLinkText,
          ),
          MatchPattern(
            type: PatternType.mobile,
            onTap: logic.clickLinkText,
          ),
          MatchPattern(
            type: PatternType.tel,
            onTap: logic.clickLinkText,
          ),
        ],
        mediaItemBuilder: (context, message) {
          return _buildMediaItem(context, message);
        },
        onTapUserProfile: handleUserProfileTap,
      );

  List<MatchPattern> _mentionPatterns(Message message) {
    if (message.contentType ==
        MessageType.groupInfoSetAnnouncementNotification) {
      return [
        MatchPattern(
          type: PatternType.custom,
          pattern: r'@[\w\u4e00-\u9fff-]+',
          onTap: (value, _) {
            final context = Get.context;
            if (context != null) AnnouncementMentionLink.open(context, value);
          },
        )
      ];
    }
    if (message.contentType != MessageType.atText) return [];
    final members = [...?message.atTextElem?.atUsersInfo]..sort((a, b) =>
        (b.groupNickname?.length ?? 0).compareTo(a.groupNickname?.length ?? 0));
    return [
      for (final member in members)
        if (member.atUserID?.isNotEmpty == true &&
            member.atUserID != OpenIM.iMManager.conversationManager.atAllTag &&
            member.groupNickname?.isNotEmpty == true)
          MatchPattern(
            type: PatternType.custom,
            pattern: '${RegExp.escape('@${member.groupNickname}')}'
                r'(?=\s|$)',
            onTap: (_, __) => handleUserProfileTap((
              userID: member.atUserID!,
              name: member.groupNickname!,
              faceURL: null,
              groupID: message.groupID,
            )),
          ),
    ];
  }

  void handleUserProfileTap(
      ({
        String userID,
        String name,
        String? faceURL,
        String? groupID
      }) userProfile) {
    final userInfo = UserInfo(
        userID: userProfile.userID,
        nickname: userProfile.name,
        faceURL: userProfile.faceURL);
    logic.viewUserInfo(userInfo);
  }

  Widget? _buildMediaItem(BuildContext context, Message message) {
    if (message.contentType != MessageType.picture &&
        message.contentType != MessageType.video) {
      return null;
    }

    if (isStickerVideoMessage(message)) {
      return _buildMediaContent(message);
    }

    // A tap on a stale painted row must not capture a newly switched account.
    final account = OpenIM.iMManager.userID;
    final chatToken = DataSp.chatToken;
    final imToken = DataSp.imToken;
    final conversationID = logic.conversationInfo.conversationID;
    final chatRoute = ModalRoute.of(context);
    bool current() =>
        !logic.isClosed &&
        account.isNotEmpty &&
        chatRoute?.isActive != false &&
        account == OpenIM.iMManager.userID &&
        chatToken == DataSp.chatToken &&
        imToken == DataSp.imToken &&
        conversationID == logic.conversationInfo.conversationID;
    return GestureDetector(
      onTap: () async {
        try {
          if (!current()) return;
          if (message.hasExpired) {
            IMViews.showToast('sdkExpired'.tr);
            return;
          }
          final gallery = await ChatPictureGallery.fromMessages(
              logic.messageList.toList(), message);
          if (!current() || !context.mounted) return;
          if (gallery.sources.isEmpty) {
            IMViews.showToast('mediaMessageUnavailable'.tr);
            return;
          }
          final locator = ChatMediaMessageLocator(
              gallery: gallery,
              isCurrent: current,
              isPositioningCurrent: () =>
                  current() && chatRoute?.isCurrent != false,
              currentMessage: (id) {
                for (final item in [
                  ...logic.messageList,
                  ...logic.scrollingCacheMessageList,
                ]) {
                  if (item.clientMsgID == id) return item;
                }
                return null;
              },
              findMessage: (id) => ChatMediaMessageLocator.findStoredMessage(
                  conversationID: conversationID, clientMsgID: id),
              jumpToMessage: logic.jumpToDateMessage,
              showFeedback: (failure) => IMViews.showToast(switch (failure) {
                    ChatMediaLocationFailure.messageUnavailable =>
                      'mediaMessageUnavailable'.tr,
                    ChatMediaLocationFailure.messageExpired => 'sdkExpired'.tr,
                    ChatMediaLocationFailure.positionFailed =>
                      'mediaViewInChatFailed'.tr,
                  }));

          await IMUtils.previewMediaFile(
              context: context,
              message: message,
              sources: gallery.sources,
              initialIndex: gallery.initialIndex,
              onAutoPlay: (index) {
                return !logic.playOnce;
              },
              muted: logic.rtcIsBusy,
              onPageChanged: (index) {
                if (current()) logic.playOnce = true;
              },
              onViewInChat: (index) async {
                await locator.viewInChat(index);
              },
              onForward: (index) {
                final target = locator.currentMessageAt(index);
                if (target != null && logic.canForward(target)) {
                  logic.forwardMessage(target);
                } else if (target != null) {
                  IMViews.showToast('mediaMessageUnavailable'.tr);
                }
              },
              onDelete: (index) {
                final target = locator.currentMessageAt(index);
                if (target != null) logic.deleteMessage(target);
              });
        } catch (_) {
          if (current()) IMViews.showToast('mediaViewInChatFailed'.tr);
        } finally {
          if (current()) logic.playOnce = false;
        }
      },
      child: MediaThumbnailHero(
        tag: message.clientMsgID!,
        child: _buildMediaContent(message),
      ),
    );
  }

  Widget _buildMediaContent(Message message) {
    final isOutgoing = message.sendID == OpenIM.iMManager.userID;

    if (message.isVideoType) {
      if (isStickerVideoMessage(message)) {
        return StickerVideoBubble(message: message);
      }
      final video = message.videoElem;
      final width = video?.snapshotWidth ?? 0;
      final height = video?.snapshotHeight ?? 0;
      final ratio =
          width > 0 && height > 0 ? (width / height).clamp(0.5, 2.0) : 0.75;
      return SizedBox(
        width: 120.w,
        height: 120.w / ratio,
        child: Stack(fit: StackFit.expand, children: [
          ChatVideoThumbnail(
            path: video?.snapshotPath,
            url: video?.snapshotUrl,
            width: 120.w,
          ),
          const Center(
              child:
                  Icon(Icons.play_circle_fill, color: Colors.white, size: 36)),
        ]),
      );
    } else {
      return ChatPictureView(
        isISend: isOutgoing,
        message: message,
      );
    }
  }

  CustomTypeInfo? _buildCustomTypeItemView(
      BuildContext context, Message message) {
    final fund = logic.fundMessageData(message);
    if (fund != null) {
      return CustomTypeInfo(Obx(() {
        final currentFund = logic.fundMessageData(message) ?? fund;
        return FundMessageCard(
            isOutgoing: message.sendID == OpenIM.iMManager.userID,
            timeText: message.sendTime == null
                ? ''
                : DateFormat('HH:mm').format(
                    DateTime.fromMillisecondsSinceEpoch(message.sendTime!)),
            message: currentFund,
            recipient: logic.fundCardRecipient(currentFund),
            packetCount: logic.fundPacketCount(currentFund),
            claimedByMe: logic.fundMessageClaimedByMe(currentFund),
            statusResolved: logic.fundMessageStatusResolved(currentFund),
            isGroupChat: logic.isGroupChat);
      }), false);
    }
    return buildChatCustomMessage(context, message,
        isGroupChat: logic.isGroupChat,
        peerName: logic.nickname.value,
        onFriendVerification: logic.sendFriendVerification,
        textScaleFactor: logic.scaleFactor.value);
  }
}
