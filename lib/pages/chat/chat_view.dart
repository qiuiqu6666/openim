import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_logic.dart';
import 'personal_sticker_panel.dart';
import 'sticker_video_bubble.dart';
import 'sticker_video_message.dart';
import 'package:openim_common/src/widgets/hold_to_record_button.dart';
import 'announcement_mention_link.dart';
import 'group_announcement_banner.dart';
import 'chat_picture_gallery.dart';
import 'mention_id.dart';
import '../contacts/contacts_logic.dart';

class ChatPage extends StatelessWidget {
  final logic = Get.find<ChatLogic>(tag: GetTags.chat);

  ChatPage({super.key});

  Widget _buildItemView(Message message) => ChatItemView(
        key: logic.itemKey(message),
        message: message,
        textScaleFactor: logic.scaleFactor.value,
        allAtMap: logic.getAtMapping(message),
        timelineStr: logic.getShowTime(message),
        sendStatusSubject: logic.sendStatusSub,
        leftNickname: logic.getNewestNickname(message),
        leftFaceUrl: logic.getNewestFaceURL(message),
        rightNickname: logic.senderName,
        rightFaceUrl: OpenIM.iMManager.userInfo.faceURL,
        showLeftNickname: !logic.isSingleChat,
        showRightNickname: false,
        onFailedToResend: () => logic.failedResend(message),
        onClickItemView: () => logic.parseClickEvent(message),
        onVoicePlayed: () => logic.markVoicePlayed(message),
        voicePlayback: logic.voicePlayback,
        messageMenus: [
          if (message.attachedInfoElem?.isPrivateChat != true &&
              [
                MessageType.text,
                MessageType.atText,
                MessageType.advancedText,
                MessageType.quote
              ].contains(message.contentType))
            PopMenuInfo(
              text: StrRes.copy,
              onTap: () => IMUtils.copy(
                text: logic.copyTextMap[message.clientMsgID] ??
                    IMUtils.parseMsg(message),
              ),
            ),
          if (logic.canForward(message))
            PopMenuInfo(
              text: StrRes.menuReply,
              onTap: () => logic.replyToMessage(message),
            ),
          if (logic.canForward(message))
            PopMenuInfo(
              text: StrRes.menuForward,
              onTap: () => logic.forwardMessage(message),
            ),
          if (logic.canForward(message))
            PopMenuInfo(
                text: 'sdkMergeForward'.tr,
                onTap: () => logic.mergeForward(message)),
          if (logic.canRevoke(message))
            PopMenuInfo(
              text: StrRes.menuRevoke,
              onTap: () => logic.revokeMessage(message),
            ),
          PopMenuInfo(
            text: StrRes.delete,
            onTap: () => logic.deleteMessage(message),
          ),
        ],
        visibilityChange: (msg, visible) {
          logic.markMessageAsRead(message, visible);
        },
        onLongPressRightAvatar: () {},
        onLongPressLeftAvatar: logic.isGroupChat
            ? () => logic.mentionMessageSender(message)
            : null,
        onTapLeftAvatar: () {
          logic.onTapLeftAvatar(message);
        },
        onVisibleTrulyText: (text) {
          logic.copyTextMap[message.clientMsgID] = text;
        },
        customTypeBuilder: _buildCustomTypeItemView,
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

    return GestureDetector(
      onTap: () async {
        try {
          final gallery =
              ChatPictureGallery.fromMessages(logic.messageList, message);
          if (gallery.sources.isEmpty) return;
          Message messageAt(int index) {
            final id = gallery.sources[index].tag;
            for (final item in logic.messageList) {
              if (item.clientMsgID == id) return item;
            }
            return message;
          }

          IMUtils.previewMediaFile(
              context: context,
              message: message,
              sources: gallery.sources,
              initialIndex: gallery.initialIndex,
              onAutoPlay: (index) {
                return !logic.playOnce;
              },
              muted: logic.rtcIsBusy,
              onPageChanged: (index) {
                logic.playOnce = true;
              },
              onForward: (index) => logic.forwardMessage(messageAt(index)),
              onDelete: (index) {
                logic.deleteMessage(messageAt(index));
              }).then((value) {
            logic.playOnce = false;
          });
        } catch (e) {
          IMViews.showToast(e.toString());
        }
      },
      child: Hero(
        tag: message.clientMsgID!,
        child: _buildMediaContent(message),
        placeholderBuilder:
            (BuildContext context, Size heroSize, Widget child) => child,
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
      final path = video?.snapshotPath;
      final url = video?.snapshotUrl;
      final width = video?.snapshotWidth ?? 0;
      final height = video?.snapshotHeight ?? 0;
      final ratio =
          width > 0 && height > 0 ? (width / height).clamp(0.5, 2.0) : 0.75;
      Widget placeholder() => const ColoredBox(color: Color(0xFF607D8B));
      final thumbnail = path != null && File(path).existsSync()
          ? Image.file(File(path),
              fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder())
          : url != null && url.isNotEmpty
              ? Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder())
              : placeholder();
      return SizedBox(
        width: 120.w,
        height: 120.w / ratio,
        child: Stack(fit: StackFit.expand, children: [
          thumbnail,
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

  CustomTypeInfo? _buildCustomTypeItemView(_, Message message) {
    final data = IMUtils.parseCustomMessage(message);
    if (null != data) {
      final viewType = data['viewType'];
      if (viewType == CustomMessageType.call) {
        final type = data['type'];
        final content = data['content'];
        final view = ChatCallItemView(type: type, content: content);
        return CustomTypeInfo(view);
      } else if (viewType == CustomMessageType.deletedByFriend ||
          viewType == CustomMessageType.blockedByFriend) {
        final view = ChatFriendRelationshipAbnormalHintView(
          name: logic.nickname.value,
          onTap: logic.sendFriendVerification,
          blockedByFriend: viewType == CustomMessageType.blockedByFriend,
          deletedByFriend: viewType == CustomMessageType.deletedByFriend,
        );
        return CustomTypeInfo(view, false, false);
      } else if (viewType == CustomMessageType.removedFromGroup) {
        return CustomTypeInfo(
          StrRes.removedFromGroupHint.toText..style = Styles.ts_8E9AB0_12sp,
          false,
          false,
        );
      } else if (viewType == CustomMessageType.groupDisbanded) {
        return CustomTypeInfo(
          StrRes.groupDisbanded.toText..style = Styles.ts_8E9AB0_12sp,
          false,
          false,
        );
      }
    }
    return null;
  }

  Widget? get _groupCallHintView => null;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FriendDisplayPreferences.changes,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    // Register a theme dependency so an already open chat refreshes when the
    // user changes appearance without changing the conversation state.
    Theme.of(context);
    return WillPopScope(
      onWillPop: logic.willPop(),
      child: Obx(() {
        final presence = logic.isSingleChat && Get.isRegistered<ContactsLogic>()
            ? Get.find<ContactsLogic>().presence.users[logic.userID]
            : null;
        return Scaffold(
            backgroundColor: Styles.c_F0F2F6,
            appBar: TitleBar.chat(
              title: logic.nickname.value,
              avatarUrl: logic.faceUrl.value,
              presenceText: logic.peerTyping.value
                  ? StrRes.typing
                  : (FriendDisplayPreferences.showOnlineStatus
                      ? presence?.label
                      : null),
              isOnline: FriendDisplayPreferences.showOnlineStatus &&
                  (presence?.displayOnline ?? false),
              isSingleChat: logic.isSingleChat,
              member: logic.memberStr,
              onCloseMultiModel: logic.exit,
              onClickMoreBtn: logic.chatSetup,
              onClickCallBtn: logic.isGroupChat ? null : logic.callAudio,
              onClickVideoBtn: logic.isGroupChat ? null : logic.callVideo,
            ),
            body: SafeArea(
              child: Column(children: [
                if (logic.isGroupChat &&
                    logic.announcement.value.trim().isNotEmpty)
                  GroupAnnouncementBanner(
                    text: logic.announcement.value,
                    version: logic.announcementVersion.value,
                    groupID: logic.groupID!,
                    userID: OpenIM.iMManager.userID,
                  ),
                Expanded(
                    child: WaterMarkBgView(
                  text: '',
                  path: logic.background.value,
                  backgroundColor: Styles.c_FFFFFF,
                  floatView: _groupCallHintView,
                  bottomView: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (logic.quotedMessage.value != null)
                        ListTile(
                          dense: true,
                          title: Text(
                            '${logic.quotedMessage.value?.senderNickname ?? ''}: ${logic.quotedMessage.value?.textElem?.content ?? StrRes.message}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: logic.clearReply,
                          ),
                        ),
                      ChatInputBox(
                        stickerPanel: PersonalStickerPanel(
                          store: logic.personalStickers,
                          onAdd: logic.addPersonalSticker,
                          onSend: logic.sendPersonalSticker,
                        ),
                        forceCloseToolboxSub: logic.forceCloseToolbox,
                        controller: logic.inputCtrl,
                        focusNode: logic.focusNode,
                        isNotInGroup: logic.isInvalidGroup,
                        enabled: !logic.sendingMuted,
                        hintText: logic.sendingMuted ? StrRes.youMuted : null,
                        directionalText: logic.directionalText(),
                        onCloseDirectional: logic.onClearDirectional,
                        onSend: (v) => logic.sendTextMsg(),
                        onTapVoice: logic.onTapRecord,
                        toolbox: ChatToolBox(
                          onTapAlbum: logic.onTapAlbum,
                          onTapFile: logic.onTapFile,
                          onTapCamera: logic.onTapCamera,
                          onTapCard: logic.onTapCard,
                          onTapLocation: logic.onTapLocation,
                          onTapCall: logic.isGroupChat ? null : logic.call,
                        ),
                        voiceRecordBar: HoldToRecordButton(
                          enabled: !logic.sendingMuted && !logic.isInvalidGroup,
                          onRecorded: logic.sendRecordedVoice,
                        ),
                      ),
                    ],
                  ),
                  child: ChatListView(
                    onTouch: () => logic.closeToolbox(),
                    itemCount: logic.messageList.length,
                    controller: logic.scrollController,
                    onScrollToBottomLoad: logic.onScrollToBottomLoad,
                    onScrollToTop: logic.onScrollToTop,
                    itemBuilder: (_, index) {
                      final message = logic.indexOfMessage(index);
                      return Obx(() => _buildItemView(message));
                    },
                  ),
                )),
              ]),
            ));
      }),
    );
  }
}
