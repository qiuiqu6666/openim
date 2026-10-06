import 'chat_inline_metadata.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatItemContainer extends StatelessWidget {
  const ChatItemContainer({
    super.key,
    required this.id,
    this.leftFaceUrl,
    this.leftAvatar,
    this.textBubbleStyle,
    this.textBubbleText,
    this.rightFaceUrl,
    this.leftNickname,
    this.rightNickname,
    this.timelineStr,
    this.onTapTimeline,
    this.timelineSemanticLabel,
    this.timeStr,
    required this.isBubbleBg,
    this.mediaOverlay = false,
    this.bareMedia = false,
    this.stickerMedia = false,
    this.standaloneCard = false,
    this.metadataBelow = false,
    this.compactBubble = false,
    required this.isISend,
    required this.hasRead,
    this.showReadStatus = true,
    this.showStatus = true,
    required this.isSending,
    required this.isSendFailed,
    this.ignorePointer = false,
    this.showLeftNickname = true,
    this.showRightNickname = false,
    required this.child,
    this.childWithStatusBuilder,
    this.embeddedStatusColor,
    this.sendStatusStream,
    this.onTapLeftAvatar,
    this.onTapRightAvatar,
    this.onLongPressRightAvatar,
    this.onLongPressLeftAvatar,
    this.onFailedToResend,
    this.messageMenus = const [],
    this.menuController,
    this.avatarSize = 44,
  });
  final String id;
  final String? leftFaceUrl;
  final Widget? leftAvatar;
  final ChatTextBubbleStyle? textBubbleStyle;
  final String? textBubbleText;
  final String? rightFaceUrl;
  final String? leftNickname;
  final String? rightNickname;
  final String? timelineStr;
  final VoidCallback? onTapTimeline;
  final String? timelineSemanticLabel;
  final String? timeStr;
  final bool isBubbleBg;
  final bool mediaOverlay;
  final bool bareMedia;
  final bool stickerMedia;
  final bool standaloneCard;
  final bool metadataBelow;
  final bool compactBubble;
  final bool isISend;
  final bool hasRead;
  final bool showReadStatus;
  final bool showStatus;
  final bool isSending;
  final bool isSendFailed;
  final bool ignorePointer;
  final bool showLeftNickname;
  final bool showRightNickname;
  final Widget child;

  /// Content that reserves a place for the same delivery state inside itself.
  final Widget Function(Widget? status)? childWithStatusBuilder;
  final Color? embeddedStatusColor;
  final Stream<MsgStreamEv<bool>>? sendStatusStream;
  final Function()? onTapLeftAvatar;
  final Function()? onTapRightAvatar;
  final Function()? onLongPressRightAvatar;
  final VoidCallback? onLongPressLeftAvatar;
  final Function()? onFailedToResend;
  final List<PopMenuInfo> messageMenus;
  final CustomPopupMenuController? menuController;
  final double avatarSize;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: FriendDisplayPreferences.changes,
        builder: (context, _) => _build(context),
      );

  Widget _build(BuildContext context) {
    return IgnorePointer(
      ignoring: ignorePointer,
      child: Column(
        children: [
          if (null != timelineStr)
            if (textBubbleStyle != null)
              Padding(
                padding: textBubbleStyle!.timelineMargin,
                child: Text(timelineStr!,
                    textAlign: TextAlign.center,
                    style: textBubbleStyle!.timelineTextStyle),
              )
            else
              ChatTimelineView(
                timeStr: timelineStr!,
                onTap: onTapTimeline,
                semanticLabel: timelineSemanticLabel,
                margin: EdgeInsets.only(bottom: 20.h),
              ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: isISend
                      ? _buildRightView(context)
                      : _buildLeftView(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChildView(BuildContext context, BubbleType type) {
    final textStyle = textBubbleStyle;
    final overlay = mediaOverlay || stickerMedia;
    final showReadStatus = this.showReadStatus &&
        (textStyle?.showReadStatus ?? true) &&
        FriendDisplayPreferences.showReadReceipts;
    final time = timeStr == null
        ? null
        : Text(timeStr!,
            style: textStyle?.metadataStyle(isISend) ??
                Styles.ts_8E9AB0_12sp.copyWith(
                    fontSize: 10.sp,
                    color: overlay ? AppTokens.onAccent : null));
    final Widget? status = !isISend || !showStatus
        ? null
        : isSendFailed
            ? ChatSendFailedView(
                id: id,
                isISend: true,
                onFailedToResend: onFailedToResend,
                isFailed: true,
                stream: sendStatusStream,
              )
            : isSending
                ? ChatDelayedStatusView(
                    isSending: true, color: embeddedStatusColor)
                : ChatReadReceiptIcon(
                    isRead: showReadStatus && hasRead,
                    size: compactBubble ? 16.w : null,
                    color: embeddedStatusColor ??
                        (overlay
                            ? AppTokens.onAccent
                            : showReadStatus && hasRead
                                ? Styles.c_0089FF
                                : Styles.c_8E9AB0),
                    semanticLabel: showReadStatus
                        ? (hasRead ? StrRes.hasRead : StrRes.unread)
                        : StrRes.sentSuccessfully,
                  );
    final metadata = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (time != null) time,
        if (status != null) ...[5.horizontalSpace, status],
      ],
    );
    final hasMetadata = time != null || status != null;
    final contentChild = childWithStatusBuilder?.call(status) ?? child;
    final content = overlay
        ? ChatMessageContentAnchor(
            messageID: id,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                  stickerMedia ? StickerBubbleLayout.radius : 12.r),
              child: Stack(
                children: [
                  if (stickerMedia && hasMetadata)
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                          minHeight: StickerBubbleLayout.metadataMinHeight),
                      child: contentChild,
                    )
                  else
                    contentChild,
                  if (!stickerMedia)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 38.h,
                      child: const IgnorePointer(
                          child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x66000000)],
                        )),
                      )),
                    ),
                  if (stickerMedia && hasMetadata)
                    Positioned.fill(
                      left: StickerBubbleLayout.metadataInset,
                      top: StickerBubbleLayout.metadataInset,
                      right: StickerBubbleLayout.metadataInset,
                      bottom: StickerBubbleLayout.metadataInset,
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.bottomRight,
                          child: IgnorePointer(
                            ignoring: !isSendFailed,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .scrim
                                    .withValues(
                                        alpha: StickerBubbleLayout
                                            .metadataBackgroundOpacity),
                                borderRadius:
                                    BorderRadius.circular(AppTokens.rSm),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: StickerBubbleLayout
                                      .metadataHorizontalPadding,
                                  vertical: StickerBubbleLayout
                                      .metadataVerticalPadding,
                                ),
                                child: metadata,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (!stickerMedia)
                    Positioned(right: 6.w, bottom: 5.h, child: metadata),
                ],
              ),
            ),
          )
        : bareMedia
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    isISend ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  ChatMessageContentAnchor(messageID: id, child: contentChild),
                  if (time != null || status != null) ...[
                    SizedBox(height: 4.h),
                    metadata,
                  ],
                ],
              )
            : standaloneCard
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isISend
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      if (time != null) ...[time, 4.verticalSpace],
                      ChatMessageContentAnchor(
                          messageID: id, child: contentChild),
                      if (status != null && childWithStatusBuilder == null) ...[
                        4.verticalSpace,
                        status
                      ],
                    ],
                  )
                : ChatMessageContentAnchor(
                    messageID: id,
                    child: ChatBubble(
                      compact: compactBubble,
                      bubbleType: type,
                      padding: textStyle?.padding,
                      borderRadius: textStyle?.radius(isISend),
                      backgroundColor: textStyle?.background(isISend),
                      constraints: textStyle == null
                          ? null
                          : BoxConstraints(maxWidth: textStyle.maxBubbleWidth),
                      // Position the bubble in the message row; do not expand its background.
                      alignment: null,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxWidth: textStyle == null
                                ? (compactBubble ? 200.w : 247.w)
                                : math.max(
                                    0,
                                    textStyle.maxBubbleWidth -
                                        textStyle.padding.horizontal)),
                        child: textStyle != null && textBubbleText != null
                            ? hasMetadata
                                ? ChatTextBubbleLayout(
                                    text: textBubbleText!,
                                    textStyle: textStyle.textStyle(isISend),
                                    timeText: timeStr ?? '',
                                    metadataTextStyle:
                                        textStyle.metadataStyle(isISend),
                                    reserveReceipt: status != null,
                                    forceSeparateFooter: metadataBelow,
                                    body: contentChild,
                                    metadata: metadata,
                                  )
                                : contentChild
                            : metadataBelow
                                ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      child,
                                      compactBubble
                                          ? 0.verticalSpace
                                          : 4.verticalSpace,
                                      metadata
                                    ],
                                  )
                                : isBubbleBg
                                    ? ChatInlineMetadata(
                                        content: child, metadata: metadata)
                                    : Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: isISend
                                            ? CrossAxisAlignment.end
                                            : CrossAxisAlignment.start,
                                        children: [
                                          if (time != null) ...[
                                            time,
                                            4.verticalSpace
                                          ],
                                          child,
                                          if (status != null) ...[
                                            4.verticalSpace,
                                            status
                                          ],
                                        ],
                                      ),
                      ),
                    ),
                  );
    if (messageMenus.isEmpty) return content;
    return ChatMessageMenu(
      menus: messageMenus,
      controller: menuController,
      isOutgoing: isISend,
      child: content,
    );
  }

  Widget _buildLeftView(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          leftAvatar ??
              AvatarView(
                width: textBubbleStyle != null ? avatarSize : avatarSize.w,
                height: textBubbleStyle != null ? avatarSize : avatarSize.h,
                isCircle: textBubbleStyle != null ? true : null,
                textStyle: textBubbleStyle?.avatarTextStyle ??
                    Styles.ts_FFFFFF_14sp_medium,
                textScaler: textBubbleStyle?.avatarTextScaler,
                url: leftFaceUrl,
                text: leftNickname,
                onTap: onTapLeftAvatar,
                onLongPress: onLongPressLeftAvatar,
              ),
          textBubbleStyle == null
              ? 10.horizontalSpace
              : SizedBox(width: textBubbleStyle!.avatarGap),
          Flexible(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (showLeftNickname && leftNickname != null) ...[
                ChatNicknameView(nickname: leftNickname),
                4.verticalSpace,
              ],
              Align(
                alignment: Alignment.centerLeft,
                child: _buildChildView(context, BubbleType.receiver),
              ),
            ],
          )),
        ],
      );

  Widget _buildRightView(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              if (showRightNickname && rightNickname != null) ...[
                ChatNicknameView(nickname: rightNickname),
                4.verticalSpace,
              ],
              Align(
                alignment: Alignment.centerRight,
                child: _buildChildView(context, BubbleType.send),
              ),
            ],
          )),
        ],
      );
}

/// Thin, rounded double check matching the message receipt design.
class ChatReadReceiptIcon extends StatelessWidget {
  const ChatReadReceiptIcon({
    super.key,
    this.isRead = true,
    this.color,
    this.semanticLabel,
    this.size,
  });
  final bool isRead;
  final Color? color;
  final String? semanticLabel;
  final double? size;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticLabel ?? (isRead ? StrRes.hasRead : StrRes.unread),
        child: CustomPaint(
          size: Size(size ?? 16.w, (size ?? 16.w) * .7),
          painter: _ReadReceiptPainter(
            color ?? (isRead ? Styles.c_0089FF : Styles.c_8E9AB0),
            isRead,
          ),
        ),
      );
}

class _ReadReceiptPainter extends CustomPainter {
  const _ReadReceiptPainter(this.color, this.isRead);

  final Color color;
  final bool isRead;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.07
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final checks = isRead
        ? (Path()
          ..moveTo(size.width * 0.08, size.height * 0.59)
          ..lineTo(size.width * 0.27, size.height * 0.82)
          ..lineTo(size.width * 0.69, size.height * 0.18)
          ..moveTo(size.width * 0.42, size.height * 0.70)
          ..lineTo(size.width * 0.52, size.height * 0.82)
          ..lineTo(size.width * 0.94, size.height * 0.18))
        : (Path()
          ..moveTo(size.width * 0.17, size.height * 0.59)
          ..lineTo(size.width * 0.36, size.height * 0.82)
          ..lineTo(size.width * 0.78, size.height * 0.18));
    canvas.drawPath(checks, paint);
  }

  @override
  bool shouldRepaint(covariant _ReadReceiptPainter oldDelegate) =>
      color != oldDelegate.color || isRead != oldDelegate.isRead;
}
