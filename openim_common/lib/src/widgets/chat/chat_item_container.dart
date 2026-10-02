import 'chat_inline_metadata.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:openim_common/openim_common.dart';

class ChatItemContainer extends StatelessWidget {
  const ChatItemContainer({
    super.key,
    required this.id,
    this.leftFaceUrl,
    this.rightFaceUrl,
    this.leftNickname,
    this.rightNickname,
    this.timelineStr,
    this.timeStr,
    required this.isBubbleBg,
    this.mediaOverlay = false,
    this.bareMedia = false,
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
    this.sendStatusStream,
    this.onTapLeftAvatar,
    this.onTapRightAvatar,
    this.onLongPressRightAvatar,
    this.onLongPressLeftAvatar,
    this.onFailedToResend,
    this.messageMenus = const [],
    this.menuController,
  });
  final String id;
  final String? leftFaceUrl;
  final String? rightFaceUrl;
  final String? leftNickname;
  final String? rightNickname;
  final String? timelineStr;
  final String? timeStr;
  final bool isBubbleBg;
  final bool mediaOverlay;
  final bool bareMedia;
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
  final Stream<MsgStreamEv<bool>>? sendStatusStream;
  final Function()? onTapLeftAvatar;
  final Function()? onTapRightAvatar;
  final Function()? onLongPressRightAvatar;
  final VoidCallback? onLongPressLeftAvatar;
  final Function()? onFailedToResend;
  final List<PopMenuInfo> messageMenus;
  final CustomPopupMenuController? menuController;

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
            ChatTimelineView(
              timeStr: timelineStr!,
              margin: EdgeInsets.only(bottom: 20.h),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: isISend ? _buildRightView() : _buildLeftView()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChildView(BubbleType type) {
    final showReadStatus =
        this.showReadStatus && FriendDisplayPreferences.showReadReceipts;
    final time = timeStr == null
        ? null
        : Text(timeStr!,
            style: Styles.ts_8E9AB0_12sp.copyWith(
                fontSize: 10.sp, color: mediaOverlay ? Colors.white : null));
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
                ? ChatDelayedStatusView(isSending: true)
                : ChatReadReceiptIcon(
                    isRead: showReadStatus && hasRead,
                    size: compactBubble ? 16.w : null,
                    color: mediaOverlay
                        ? Colors.white
                        : showReadStatus && hasRead
                            ? Styles.c_0089FF
                            : Styles.c_8E9AB0,
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
    final content = mediaOverlay
        ? ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: Stack(
              children: [
                child,
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
                Positioned(right: 6.w, bottom: 5.h, child: metadata),
              ],
            ),
          )
        : bareMedia
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment:
                    isISend ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  child,
                  if (time != null || status != null) ...[
                    4.verticalSpace,
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
                      child,
                      if (status != null) ...[4.verticalSpace, status],
                    ],
                  )
                : ChatBubble(
                    compact: compactBubble,
                    bubbleType: type,
                    // Position the bubble in the message row; do not expand its background.
                    alignment: null,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxWidth: compactBubble ? 200.w : 247.w),
                      child: metadataBelow
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
                  );
    if (messageMenus.isEmpty) return content;
    return PopButton(
      menus: messageMenus,
      popCtrl: menuController,
      pressType: PressType.longPress,
      child: content,
    );
  }

  Widget _buildLeftView() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          AvatarView(
            width: 44.w,
            height: 44.h,
            textStyle: Styles.ts_FFFFFF_14sp_medium,
            url: leftFaceUrl,
            text: leftNickname,
            onTap: onTapLeftAvatar,
            onLongPress: onLongPressLeftAvatar,
          ),
          10.horizontalSpace,
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
                child: _buildChildView(BubbleType.receiver),
              ),
            ],
          )),
        ],
      );

  Widget _buildRightView() => Row(
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
                child: _buildChildView(BubbleType.send),
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
