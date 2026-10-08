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
import 'contact_card/contact_card_identity_view.dart';
import 'markdown/chat_message_text_source.dart';
import 'quote/chat_quote_card.dart';

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
    super.key,
    this.mediaItemBuilder,
    this.itemViewBuilder,
    this.customTypeBuilder,
    this.notificationTypeBuilder,
    this.sendStatusSubject,
    this.visibilityChange,
    this.timelineStr,
    this.onTapTimeline,
    this.timelineSemanticLabel,
    this.leftNickname,
    this.leftFaceUrl,
    this.leftAvatar,
    this.textContentBuilder,
    this.textBubbleStyle,
    this.rightNickname,
    this.rightFaceUrl,
    required this.message,
    this.textScaleFactor = 1.0,
    this.ignorePointer = false,
    this.showLeftNickname = true,
    this.showRightNickname = false,
    this.isStickerMedia = false,
    this.itemMargin,
    this.itemPadding,
    this.avatarSize,
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
    this.voiceTranscription,
    this.onToggleVoiceTranscription,
    this.onRetryVoiceTranscription,
    this.messageMenus = const [],
    required this.onTapUserProfile,
  });
  final ItemViewBuilder? mediaItemBuilder;
  final ItemViewBuilder? itemViewBuilder;
  final CustomTypeBuilder? customTypeBuilder;
  final NotificationTypeBuilder? notificationTypeBuilder;

  final Subject<MsgStreamEv<bool>>? sendStatusSubject;

  final ItemVisibilityChange? visibilityChange;
  final String? timelineStr;
  final VoidCallback? onTapTimeline;
  final String? timelineSemanticLabel;
  final String? leftNickname;
  final String? leftFaceUrl;
  final Widget? leftAvatar;

  /// Alternative text content preserves the container's menus and receipts.
  final ItemViewBuilder? textContentBuilder;
  final ChatTextBubbleStyle? textBubbleStyle;
  final String? rightNickname;
  final String? rightFaceUrl;
  final Message message;

  final Future<void> Function()? onVoicePlayed;
  final VoicePlaybackController? voicePlayback;
  final VoiceTranscriptionState? voiceTranscription;
  final VoidCallback? onToggleVoiceTranscription;
  final VoidCallback? onRetryVoiceTranscription;
  final double textScaleFactor;
  final bool ignorePointer;
  final bool showLeftNickname;
  final bool showRightNickname;
  final bool isStickerMedia;

  /// Optional compact layout for read-only message surfaces such as previews.
  final EdgeInsetsGeometry? itemMargin;
  final EdgeInsetsGeometry? itemPadding;
  final double? avatarSize;

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

  ChatTextBubbleStyle? get _textBubbleStyle =>
      _message.contentType == MessageType.text ? widget.textBubbleStyle : null;

  @override
  Widget build(BuildContext context) {
    final sticker = widget.isStickerMedia ||
        _message.contentType == MessageType.customFace ||
        _message.isEmojiType ||
        _message.isDiceType;
    final content = Container(
      color: widget.highlightColor,
      margin: widget.itemMargin ??
          _textBubbleStyle?.rowMargin ??
          EdgeInsets.only(bottom: sticker ? StickerBubbleLayout.rowGap : 20.h),
      padding: widget.itemPadding ??
          _textBubbleStyle?.rowPadding(_isISend) ??
          EdgeInsets.symmetric(
              horizontal: sticker ? StickerBubbleLayout.rowInset : 10.w),
      child: Center(child: _child),
    );
    // Passive previews have no visibility/read callback. They need neither a
    // focus observer nor its deferred visibility timer.
    if (widget.visibilityChange == null) {
      return content;
    }
    return FocusDetector(
      child: content,
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
    Widget Function(Widget? status)? cardWithStatus;
    String? senderNickname;
    String? senderFaceURL;
    bool isBubbleBg = false;
    bool markdownContent = false;
    late final textSource = chatMessageTextSource(_message);
    Widget textContent({bool useOverride = true}) {
      final override = useOverride
          ? widget.textContentBuilder?.call(context, _message)
          : null;
      if (override != null) return override;
      final allowMarkdown = chatMessageAllowsMarkdown(_message);
      markdownContent =
          allowMarkdown && ChatMarkdownText.hasMarkdown(textSource);
      return ChatText(
        text: textSource,
        enableMarkdown: allowMarkdown,
        textStyle: _textBubbleStyle?.textStyle(_isISend),
        maximumWidth: _textBubbleStyle == null ? null : double.infinity,
        textScaler:
            _textBubbleStyle == null ? null : MediaQuery.textScalerOf(context),
        matchTextStyle: _textBubbleStyle?.textStyle(_isISend).copyWith(
            color: ThemeData.estimateBrightnessForColor(
                        _textBubbleStyle!.background(_isISend)) ==
                    Brightness.dark
                ? AppTokens.onAccent
                : AppTokens.accent),
        patterns: widget.patterns,
        textScaleFactor: widget.textScaleFactor,
        onVisibleTrulyText: widget.onVisibleTrulyText,
      );
    }

    /* if (_message.isCallType) {
    } else if (_message.isMeetingType) {
    } else if (_message.isDeletedByFriendType) {
    } else if (_message.isBlockedByFriendType) {
    } else if (_message.isEmojiType) {
    } else if (_message.isTagType) {
    }*/
    if (_message.contentType == MessageType.advancedText) {
      isBubbleBg = true;
      final entities = _message.advancedTextElem?.messageEntityList ?? [];
      child = widget.textContentBuilder?.call(context, _message) ??
          (entities.isEmpty
              ? textContent(useOverride: false)
              : ChatFormattedText(text: textSource, entities: entities));
    } else if (_message.isTextType ||
        _message.contentType == MessageType.atText) {
      isBubbleBg = true;
      child = textContent();
    } else if (_message.contentType == MessageType.quote) {
      isBubbleBg = true;
      child = textContent();
    } else if ([
          MessageType.merger,
          MessageType.location,
          MessageType.customFace
        ].contains(_message.contentType) ||
        _message.isEmojiType ||
        _message.isDiceType) {
      child = ChatStructuredMessage(
          message: _message, depth: widget.structuredDepth);
    } else if (_message.isVideoType) {
      child = widget.mediaItemBuilder?.call(context, _message);
    } else if (_message.isVoiceType && _message.soundElem != null) {
      child = ChatVoiceMessageView(
          message: _message,
          isOutgoing: _isISend,
          readOnly: widget.ignorePointer,
          onPlayed: widget.onVoicePlayed,
          playback: widget.voicePlayback);
      if (widget.voiceTranscription != null) {
        child = SizedBox(
          width: maxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child,
              VoiceTranscriptionView(
                state: widget.voiceTranscription!,
                selectable: _message.attachedInfoElem?.isPrivateChat != true,
                onToggle: widget.onToggleVoiceTranscription,
                onRetry: widget.onRetryVoiceTranscription,
              ),
            ],
          ),
        );
      }
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
      cardWithStatus = (status) => ContactCardIdentityView(
            card: card,
            status: status,
            isSelf: _isISend,
            time: DateFormat('HH:mm').format(
                DateTime.fromMillisecondsSinceEpoch(_message.sendTime!)),
          );
      child = cardWithStatus(null);
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

    // Mention replies carry their reference in atTextElem instead of quoteElem.
    // Apply the same card after choosing the body so both live chat and peek
    // retain the reply's text/mention formatting and its referenced message.
    final quoted =
        _message.quoteElem?.quoteMessage ?? _message.atTextElem?.quoteMessage;
    if (_message.contentType == MessageType.quote ||
        (quoted != null &&
            [MessageType.text, MessageType.atText, MessageType.advancedText]
                .contains(_message.contentType))) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ChatQuoteCard(
            message: quoted,
            bubbleColor: _isISend
                ? Styles.c_CCE7FE
                : ChatBubbleTokens.incoming(
                    dark: Theme.of(context).brightness == Brightness.dark),
          ),
          const SizedBox(height: AppTokens.s3),
          child!,
        ],
      );
    }

    senderNickname ??= widget.leftNickname ?? _message.senderNickname;
    senderFaceURL ??= widget.leftFaceUrl ?? _message.senderFaceUrl;
    final isFund = _message.isCustomType &&
        FundMessageData.tryParse(_message.customElem?.data) != null;
    Widget interactiveContent(Widget? status) {
      Widget content = cardWithStatus?.call(status) ??
          child ??
          ChatText(text: StrRes.unsupportedMessage);
      if (_message.attachedInfoElem?.isPrivateChat == true) {
        content = ChatExpiringContent(message: _message, child: content);
      }
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          final deadline = ChatExpiringContent.deadline(_message);
          if (deadline == null || deadline.isAfter(DateTime.now())) {
            widget.onClickItemView?.call();
          }
        },
        child: content,
      );
    }

    final content = interactiveContent(null);
    return ChatItemContainer(
      id: _message.clientMsgID!,
      isISend: _isISend,
      leftNickname: senderNickname,
      leftFaceUrl: senderFaceURL,
      leftAvatar: widget.leftAvatar,
      textBubbleStyle: _textBubbleStyle,
      textBubbleText: _textBubbleStyle == null ? null : textSource,
      rightNickname: widget.rightNickname ?? OpenIM.iMManager.userInfo.nickname,
      rightFaceUrl: widget.rightFaceUrl ?? OpenIM.iMManager.userInfo.faceURL,
      showLeftNickname: widget.showLeftNickname,
      showRightNickname: widget.showRightNickname,
      timelineStr: widget.timelineStr,
      onTapTimeline: widget.onTapTimeline,
      timelineSemanticLabel: widget.timelineSemanticLabel,
      timeStr: isFund ||
              _message.isCardType ||
              _message.contentType ==
                  MessageType.groupInfoSetAnnouncementNotification
          ? null
          : DateFormat('HH:mm').format(
              DateTime.fromMillisecondsSinceEpoch(_message.sendTime!),
            ),
      hasRead: _message.isRead ?? false,
      showReadStatus: !isFund && _message.isSingleChat,
      showStatus: !isFund &&
          _message.contentType !=
              MessageType.groupInfoSetAnnouncementNotification,
      isSending: _message.status == MessageStatus.sending,
      isSendFailed: _message.status == MessageStatus.failed,
      isBubbleBg: isBubbleBg,
      avatarSize: widget.avatarSize ??
          _textBubbleStyle?.avatarSize ??
          (isFund ? FundTokens.chatAvatarSize : 44),
      bareMedia: _message.contentType == MessageType.customFace ||
          _message.isEmojiType ||
          _message.isDiceType ||
          widget.isStickerMedia ||
          (_message.isCustomType &&
              FundMessageData.tryParse(_message.customElem?.data) != null),
      compactBubble: _message.isVoiceType ||
          _message.isFileType ||
          (_message.isCustomType &&
              IMUtils.parseCustomMessage(_message)?['viewType'] ==
                  CustomMessageType.call),
      metadataBelow: markdownContent ||
          _message.isVoiceType ||
          _message.isFileType ||
          _message.isCustomType ||
          [MessageType.merger, MessageType.location, MessageType.customFace]
              .contains(_message.contentType),
      mediaOverlay: widget.isStickerMedia ||
          _message.contentType == MessageType.customFace ||
          _message.isEmojiType ||
          _message.isDiceType ||
          _message.isPictureType ||
          _message.isVideoType,
      stickerMedia: widget.isStickerMedia ||
          _message.contentType == MessageType.customFace ||
          _message.isEmojiType ||
          _message.isDiceType,
      standaloneCard: (_message.isCardType && _message.cardElem != null) ||
          _message.contentType ==
              MessageType.groupInfoSetAnnouncementNotification,
      childWithStatusBuilder:
          cardWithStatus == null ? null : interactiveContent,
      embeddedStatusColor:
          cardWithStatus == null ? null : ContactCardTokens.footerText,
      ignorePointer: widget.ignorePointer,
      sendStatusStream: widget.sendStatusSubject,
      onFailedToResend: widget.onFailedToResend,
      onLongPressRightAvatar: widget.onLongPressRightAvatar,
      onTapLeftAvatar: widget.onTapLeftAvatar,
      onLongPressLeftAvatar: widget.onLongPressLeftAvatar,
      onTapRightAvatar: widget.onTapRightAvatar,
      messageMenus: widget.messageMenus,
      menuController: _menuController,
      child: content,
    );
  }
}
