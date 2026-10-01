import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:focus_detector_v2/focus_detector_v2.dart';
import 'package:openim_common/openim_common.dart';
import 'package:rxdart/rxdart.dart';

import 'chat_notice_view.dart';
import 'chat_attachment_view.dart';
import 'chat_structured_message.dart';
import 'chat_formatted_text.dart';
import 'chat_expiring_content.dart';

double maxWidth = 247.w;
double pictureWidth = 120.w;
double videoWidth = 120.w;
double locationWidth = 220.w;

BorderRadius borderRadius(bool isISend) => BorderRadius.only(
      topLeft: Radius.circular(isISend ? 6.r : 0),
      topRight: Radius.circular(isISend ? 0 : 6.r),
      bottomLeft: Radius.circular(6.r),
      bottomRight: Radius.circular(6.r),
    );

class MsgStreamEv<T> {
  final String id;
  final T value;

  MsgStreamEv({required this.id, required this.value});

  @override
  String toString() {
    return 'MsgStreamEv{msgId: $id, value: $value}';
  }
}

class CustomTypeInfo {
  final Widget customView;
  final bool needBubbleBackground;
  final bool needChatItemContainer;

  CustomTypeInfo(
    this.customView, [
    this.needBubbleBackground = true,
    this.needChatItemContainer = true,
  ]);
}

typedef CustomTypeBuilder = CustomTypeInfo? Function(
  BuildContext context,
  Message message,
);
typedef NotificationTypeBuilder = Widget? Function(
  BuildContext context,
  Message message,
);
typedef ItemViewBuilder = Widget? Function(
  BuildContext context,
  Message message,
);
typedef ItemVisibilityChange = void Function(
  Message message,
  bool visible,
);

class ChatItemView extends StatefulWidget {
  const ChatItemView({
    Key? key,
    this.mediaItemBuilder,
    this.itemViewBuilder,
    this.customTypeBuilder,
    this.notificationTypeBuilder,
    this.sendStatusSubject,
    this.visibilityChange,
    this.timelineStr,
    this.leftNickname,
    this.leftFaceUrl,
    this.rightNickname,
    this.rightFaceUrl,
    required this.message,
    this.textScaleFactor = 1.0,
    this.ignorePointer = false,
    this.showLeftNickname = true,
    this.showRightNickname = false,
    this.highlightColor,
    this.allAtMap = const {},
    this.patterns = const [],
    this.structuredDepth = 0,
    this.onTapLeftAvatar,
    this.onLongPressLeftAvatar,
    this.onTapRightAvatar,
    this.onLongPressRightAvatar,
    this.onVisibleTrulyText,
    this.onFailedToResend,
    this.onClickItemView,
    this.onVoicePlayed,
    this.voicePlayback,
    this.messageMenus = const [],
    required this.onTapUserProfile,
  }) : super(key: key);
  final ItemViewBuilder? mediaItemBuilder;
  final ItemViewBuilder? itemViewBuilder;
  final CustomTypeBuilder? customTypeBuilder;
  final NotificationTypeBuilder? notificationTypeBuilder;

  final Subject<MsgStreamEv<bool>>? sendStatusSubject;

  final ItemVisibilityChange? visibilityChange;
  final String? timelineStr;
  final String? leftNickname;
  final String? leftFaceUrl;
  final String? rightNickname;
  final String? rightFaceUrl;
  final Message message;

  final Future<void> Function()? onVoicePlayed;
  final VoicePlaybackController? voicePlayback;
  final double textScaleFactor;
  final bool ignorePointer;
  final bool showLeftNickname;
  final bool showRightNickname;

  final Color? highlightColor;
  final Map<String, String> allAtMap;
  final List<MatchPattern> patterns;
  final int structuredDepth;
  final Function()? onTapLeftAvatar;
  final VoidCallback? onLongPressLeftAvatar;
  final Function()? onTapRightAvatar;
  final Function()? onLongPressRightAvatar;
  final Function(String? text)? onVisibleTrulyText;
  final Function()? onClickItemView;
  final List<PopMenuInfo> messageMenus;
  final ValueChanged<
          ({String userID, String name, String? faceURL, String? groupID})>
      onTapUserProfile;

  final Function()? onFailedToResend;
  @override
  State<ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<ChatItemView> {
  final _menuController = CustomPopupMenuController();

  @override
  void dispose() {
    _menuController.dispose();
    super.dispose();
  }

  Message get _message => widget.message;

  bool get _isISend => _message.sendID == OpenIM.iMManager.userID;

  @override
  Widget build(BuildContext context) {
    return FocusDetector(
      child: Container(
        color: widget.highlightColor,
        margin: EdgeInsets.only(bottom: 20.h),
        padding: EdgeInsets.symmetric(horizontal: 10.w),
        child: Center(child: _child),
      ),
      onVisibilityLost: () {
        widget.visibilityChange?.call(widget.message, false);
      },
      onVisibilityGained: () {
        widget.visibilityChange?.call(widget.message, true);
      },
    );
  }

  Widget get _child =>
      widget.itemViewBuilder?.call(context, _message) ?? _buildChildView();

  Widget _buildChildView() {
    Widget? child;
    String? senderNickname;
    String? senderFaceURL;
    bool isBubbleBg = false;
    /* if (_message.isCallType) {
    } else if (_message.isMeetingType) {
    } else if (_message.isDeletedByFriendType) {
    } else if (_message.isBlockedByFriendType) {
    } else if (_message.isEmojiType) {
    } else if (_message.isTagType) {
    }*/
    if (_message.contentType == MessageType.advancedText) {
      isBubbleBg = true;
      child = ChatFormattedText(
          text: _message.advancedTextElem?.text ?? '',
          entities: _message.advancedTextElem?.messageEntityList ?? []);
    } else if (_message.isTextType ||
        _message.contentType == MessageType.atText ||
        _message.contentType == MessageType.advancedText) {
      isBubbleBg = true;
      child = ChatText(
        text: IMUtils.parseMsg(_message),
        patterns: widget.patterns,
        textScaleFactor: widget.textScaleFactor,
        onVisibleTrulyText: widget.onVisibleTrulyText,
      );
    } else if (_message.contentType == MessageType.quote) {
      isBubbleBg = true;
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatText(
            text: _message.quoteElem?.text ?? '',
            patterns: widget.patterns,
            textScaleFactor: widget.textScaleFactor,
          ),
          const SizedBox(height: 4),
          Text(
            '${_message.quoteElem?.quoteMessage?.senderNickname ?? ''}: ${_message.quoteElem?.quoteMessage == null ? '' : IMUtils.parseMsg(_message.quoteElem!.quoteMessage!)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Styles.ts_8E9AB0_12sp,
          ),
        ],
      );
    } else if ([
          MessageType.merger,
          MessageType.location,
          MessageType.customFace
        ].contains(_message.contentType) ||
        _message.isEmojiType) {
      child = ChatStructuredMessage(
          message: _message, depth: widget.structuredDepth);
    } else if (_message.isVideoType) {
      child = widget.mediaItemBuilder?.call(context, _message);
    } else if (_message.isVoiceType && _message.soundElem != null) {
      child = ChatVoiceMessageView(
          message: _message,
          isOutgoing: _isISend,
          onPlayed: widget.onVoicePlayed,
          playback: widget.voicePlayback);
    } else if (_message.isFileType && _message.fileElem != null) {
      child = ChatFileMessageView(message: _message);
    } else if (_message.isCustomType) {
      final custom = widget.customTypeBuilder?.call(context, _message);
      if (custom != null) {
        if (!custom.needChatItemContainer) return custom.customView;
        child = custom.customView;
        isBubbleBg = custom.needBubbleBackground;
      }
    } else if (_message.isCardType && _message.cardElem != null) {
      final card = _message.cardElem!;
      child = ContactCardView(
        userID: card.userID ?? '',
        name: card.nickname?.trim().isNotEmpty == true
            ? card.nickname!.trim()
            : card.userID ?? '',
        faceURL: card.faceURL,
        isSelf: _isISend,
        time: DateFormat('HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(_message.sendTime!)),
      );
    } else if (_message.isPictureType) {
      child = widget.mediaItemBuilder?.call(context, _message) ??
          ChatPictureView(
            isISend: _isISend,
            message: _message,
          );
    } else if (_message.isNotificationType) {
      if (_message.contentType ==
          MessageType.groupInfoSetAnnouncementNotification) {
        final map = json.decode(_message.notificationElem!.detail!);
        final ntf = GroupNotification.fromJson(map);
        final noticeContent = ntf.group?.notification;
        senderNickname = ntf.opUser?.nickname;
        senderFaceURL = ntf.opUser?.faceURL;
        child = ChatNoticeView(
          patterns: widget.patterns,
          isISend: _isISend,
          content: noticeContent ?? '',
          time: _message.sendTime == null
              ? null
              : DateFormat('HH:mm').format(
                  DateTime.fromMillisecondsSinceEpoch(_message.sendTime!)),
        );
      } else {
        return ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: ChatHintTextView(
            message: _message,
            onTapUserProfile: widget.onTapUserProfile,
          ),
        );
      }
    }

    if (child != null && _message.attachedInfoElem?.isPrivateChat == true) {
      child = ChatExpiringContent(message: _message, child: child);
    }
    senderNickname ??= widget.leftNickname ?? _message.senderNickname;
    senderFaceURL ??= widget.leftFaceUrl ?? _message.senderFaceUrl;
    return child = ChatItemContainer(
      id: _message.clientMsgID!,
      isISend: _isISend,
      leftNickname: senderNickname,
      leftFaceUrl: senderFaceURL,
      rightNickname: widget.rightNickname ?? OpenIM.iMManager.userInfo.nickname,
      rightFaceUrl: widget.rightFaceUrl ?? OpenIM.iMManager.userInfo.faceURL,
      showLeftNickname: widget.showLeftNickname,
      showRightNickname: widget.showRightNickname,
      timelineStr: widget.timelineStr,
      timeStr: _message.isCardType ||
              _message.contentType ==
                  MessageType.groupInfoSetAnnouncementNotification
          ? null
          : DateFormat('HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(_message.sendTime!),
            ),
      hasRead: _message.isRead!,
      showReadStatus: _message.isSingleChat,
      showStatus: _message.contentType !=
          MessageType.groupInfoSetAnnouncementNotification,
      isSending: _message.status == MessageStatus.sending,
      isSendFailed: _message.status == MessageStatus.failed,
      isBubbleBg: isBubbleBg,
      bareMedia: _message.contentType == MessageType.customFace ||
          _message.isEmojiType,
      compactBubble: _message.isVoiceType || _message.isFileType ||
          (_message.isCustomType &&
              IMUtils.parseCustomMessage(_message)?['viewType'] ==
                  CustomMessageType.call),
      metadataBelow: _message.isVoiceType ||
          _message.isFileType ||
          _message.isCustomType ||
          [MessageType.merger, MessageType.location, MessageType.customFace]
              .contains(_message.contentType),
      mediaOverlay: _message.isPictureType || _message.isVideoType,
      standaloneCard: (_message.isCardType && _message.cardElem != null) ||
          _message.contentType ==
              MessageType.groupInfoSetAnnouncementNotification,
      ignorePointer: widget.ignorePointer,
      sendStatusStream: widget.sendStatusSubject,
      onFailedToResend: widget.onFailedToResend,
      onLongPressRightAvatar: widget.onLongPressRightAvatar,
      onTapLeftAvatar: widget.onTapLeftAvatar,
      onLongPressLeftAvatar: widget.onLongPressLeftAvatar,
      onTapRightAvatar: widget.onTapRightAvatar,
      messageMenus: widget.messageMenus,
      menuController: _menuController,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final deadline = ChatExpiringContent.deadline(_message);
          if (deadline == null || deadline.isAfter(DateTime.now()))
            widget.onClickItemView?.call();
        },
        child: child ?? ChatText(text: StrRes.unsupportedMessage),
      ),
    );
  }
}
