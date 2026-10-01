import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_logic.dart';
import 'chat_picture_gallery.dart';
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
        messageMenus: [
          if (message.isTextType || message.contentType == MessageType.quote)
            PopMenuInfo(
              text: StrRes.copy,
              onTap: () => IMUtils.copy(
                text: logic.copyTextMap[message.clientMsgID] ??
                    message.textElem?.content ??
                    message.quoteElem?.text ??
                    '',
              ),
            ),
          if (message.isTextType || message.contentType == MessageType.quote)
            PopMenuInfo(
              text: StrRes.menuReply,
              onTap: () => logic.replyToMessage(message),
            ),
          if (message.isTextType ||
              message.isPictureType ||
              message.contentType == MessageType.quote)
            PopMenuInfo(
              text: StrRes.menuForward,
              onTap: () => logic.forwardMessage(message),
            ),
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
        onTapLeftAvatar: () {
          logic.onTapLeftAvatar(message);
        },
        onVisibleTrulyText: (text) {
          logic.copyTextMap[message.clientMsgID] = text;
        },
        customTypeBuilder: _buildCustomTypeItemView,
        patterns: <MatchPattern>[
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

    return GestureDetector(
      onTap: () async {
        try {
          final gallery =
              ChatPictureGallery.fromMessages(logic.messageList, message);
          if (gallery != null && gallery.sources.isEmpty) return;
          Message messageAt(int index) {
            final id = gallery!.sources[index].tag;
            for (final item in logic.messageList) {
              if (item.clientMsgID == id) return item;
            }
            return message;
          }

          IMUtils.previewMediaFile(
                  context: context,
                  message: message,
                  sources: gallery?.sources,
                  initialIndex: gallery?.initialIndex ?? 0,
                  onAutoPlay: (index) {
                    return !logic.playOnce;
                  },
                  muted: logic.rtcIsBusy,
                  onPageChanged: (index) {
                    logic.playOnce = true;
                  },
                  onForward: gallery == null
                      ? null
                      : (index) => logic.forwardMessage(messageAt(index)),
                  onDelete: gallery == null
                      ? null
                      : (index) {
                          logic.deleteMessage(messageAt(index));
                        })
              .then((value) {
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
  Widget build(BuildContext context) {
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
              presenceText: presence?.label,
              isOnline: presence?.displayOnline ?? false,
              isSingleChat: logic.isSingleChat,
              member: logic.memberStr,
              onCloseMultiModel: logic.exit,
              onClickMoreBtn: logic.chatSetup,
              onClickCallBtn: logic.isGroupChat ? null : logic.callAudio,
              onClickVideoBtn: logic.isGroupChat ? null : logic.callVideo,
            ),
            body: SafeArea(
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
                      forceCloseToolboxSub: logic.forceCloseToolbox,
                      controller: logic.inputCtrl,
                      focusNode: logic.focusNode,
                      isNotInGroup: logic.isInvalidGroup,
                      directionalText: logic.directionalText(),
                      onCloseDirectional: logic.onClearDirectional,
                      onSend: (v) => logic.sendTextMsg(),
                      toolbox: ChatToolBox(
                        onTapAlbum: logic.onTapAlbum,
                        onTapAudio: logic.onTapAudio,
                        onTapFile: logic.onTapFile,
                        onTapCamera: logic.onTapCamera,
                        onTapRecord: logic.onTapRecord,
                        onTapCard: logic.onTapCard,
                        onTapCall: logic.isGroupChat ? null : logic.call,
                      ),
                      voiceRecordBar: const SizedBox(),
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
              ),
            ));
      }),
    );
  }
}
