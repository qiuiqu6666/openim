import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

class TitleBar extends StatelessWidget implements PreferredSizeWidget {
  static double get chatToolbarHeight => NavigationGlassTokens.toolbarHeight;

  /// Keeps the regular toolbar while allowing both text lines to scale.
  static double chatToolbarHeightFor(BuildContext context,
      {bool hasSubtitle = true, bool isSingleChat = true}) {
    // A caller calculates the app-bar size before Scaffold installs Material's
    // default text style, so use that same theme style for measurement.
    final inherited = Theme.of(context).textTheme.bodyMedium ??
        DefaultTextStyle.of(context).style;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double lineHeight(TextStyle style, {StrutStyle? strutStyle}) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag国', style: inherited.merge(style)),
        textDirection: direction,
        textScaler: scaler,
        strutStyle: strutStyle,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    final titleHeight = lineHeight(Styles.ts_0C1C33_17sp);
    final subtitleHeight = hasSubtitle
        ? lineHeight(TextStyle(fontSize: 11.sp),
            strutStyle: isSingleChat
                ? StrutStyle(fontSize: 11.sp, forceStrutHeight: true)
                : null)
        : 0.0;
    return math.max(
        chatToolbarHeight, titleHeight + subtitleHeight + AppTokens.s3.h);
  }

  const TitleBar({
    Key? key,
    this.height,
    this.left,
    this.center,
    this.right,
    this.backgroundColor,
    this.showUnderline = false,
  }) : super(key: key);
  final double? height;
  final Widget? left;
  final Widget? center;
  final Widget? right;
  final Color? backgroundColor;
  final bool showUnderline;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemBars.styleFor(
          backgroundColor ?? NavigationGlassTokens.backgroundColor(context)),
      child: LiquidGlassSurface(
        tint: backgroundColor,
        child: Padding(
          padding: EdgeInsets.only(top: mq.padding.top),
          child: Container(
            height: height ?? NavigationGlassTokens.toolbarHeight,
            padding: EdgeInsets.symmetric(horizontal: 16.w),
            decoration: showUnderline
                ? BoxDecoration(
                    border: BorderDirectional(
                      bottom: BorderSide(color: Styles.c_E8EAEF, width: .5),
                    ),
                  )
                : null,
            child: Row(
              children: [
                if (null != left) left!,
                if (null != center) center!,
                if (null != right) right!,
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Size get preferredSize =>
      Size.fromHeight(height ?? NavigationGlassTokens.toolbarHeight);

  TitleBar.conversation(
      {super.key,
      String? statusStr,
      bool isFailed = false,
      Function()? onAddFriend,
      Function()? onAddGroup,
      Function()? onCreateGroup,
      CustomPopupMenuController? popCtrl,
      this.left})
      : backgroundColor = null,
        height = NavigationGlassTokens.toolbarHeight,
        showUnderline = false,
        center = null,
        right = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopButton(
              popCtrl: popCtrl,
              menus: [
                PopMenuInfo(
                  text: StrRes.addFriend,
                  iconWidget: AppIcon(
                      kind: AppIconKind.addFriend, size: AppIconTokens.medium),
                  onTap: onAddFriend,
                ),
                PopMenuInfo(
                  text: StrRes.addGroup,
                  iconWidget: AppIcon(
                      kind: AppIconKind.addGroup, size: AppIconTokens.medium),
                  onTap: onAddGroup,
                ),
                PopMenuInfo(
                  text: StrRes.createGroup,
                  iconWidget: AppIcon(
                      kind: AppIconKind.createGroup,
                      size: AppIconTokens.medium),
                  onTap: onCreateGroup,
                ),
              ],
              child: Semantics(
                label: StrRes.add,
                button: true,
                child: const SizedBox.square(
                  dimension: AppIconTokens.androidTouchTarget,
                  child: Center(child: AppIcon(kind: AppIconKind.add)),
                ),
              ),
            ),
          ],
        );

  TitleBar.chat({
    super.key,
    double? toolbarHeight,
    String? title,
    String? avatarUrl,
    String? presenceText,
    bool isOnline = false,
    String? member,
    bool isSingleChat = false,
    bool isMultiModel = false,
    bool showCallBtn = true,
    bool isMuted = false,
    Function()? onClickCallBtn,
    Function()? onClickVideoBtn,
    Function()? onClickMoreBtn,
    Function()? onCloseMultiModel,
  })  : backgroundColor = null,
        height = toolbarHeight ?? chatToolbarHeight,
        showUnderline = false,
        center = Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onClickMoreBtn,
            child: Row(
              children: [
                Stack(clipBehavior: Clip.none, children: [
                  AvatarView(
                    width: 32.w,
                    height: 32.w,
                    url: avatarUrl,
                    text: title,
                    isCircle: true,
                    isGroup: !isSingleChat,
                  ),
                  if (isSingleChat && isOnline)
                    Positioned(
                        right: -1.w,
                        bottom: -1.h,
                        child: Container(
                            width: 9.w,
                            height: 9.w,
                            decoration: BoxDecoration(
                                color: Styles.c_18E875,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Styles.c_FFFFFF, width: 1.5.w))))
                ]),
                8.horizontalSpace,
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title?.trim() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Styles.ts_0C1C33_17sp),
                      // Keep one status line while presence loads or is hidden.
                      // Empty text preserves its geometry without inventing a
                      // status or retaining the previous label in semantics.
                      if (isSingleChat || member != null)
                        Text(isSingleChat ? (presenceText ?? '') : member!,
                            key: isSingleChat
                                ? const ValueKey('chat-header-presence')
                                : null,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            strutStyle: isSingleChat
                                ? StrutStyle(
                                    fontSize: 11.sp, forceStrutHeight: true)
                                : null,
                            style: TextStyle(
                                color: isOnline
                                    ? Styles.c_0089FF
                                    : Styles.c_8E9AB0,
                                fontSize: 11.sp))
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        left = SizedBox(
            width: 32.w,
            child: isMultiModel
                ? (StrRes.cancel.toText
                  ..style = Styles.ts_0C1C33_17sp
                  ..onTap = onCloseMultiModel)
                : Transform.translate(
                    offset: Offset(-8.w, 0),
                    child: ImageRes.backBlack.toImage
                      ..width = 24.w
                      ..height = 24.h
                      ..color = Styles.c_0089FF
                      ..onTap = (() => Get.back()))),
        right = isSingleChat
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: Icon(CupertinoIcons.phone_fill,
                        color: Styles.c_0089FF, size: 23.w),
                    tooltip: StrRes.callVoice,
                    onPressed: isMuted ? null : onClickCallBtn,
                    constraints:
                        BoxConstraints.tightFor(width: 40.w, height: 40.h),
                    padding: EdgeInsets.zero),
                IconButton(
                    icon: Icon(CupertinoIcons.videocam_fill,
                        color: Styles.c_0089FF, size: 25.w),
                    tooltip: StrRes.callVideo,
                    onPressed: isMuted ? null : onClickVideoBtn,
                    constraints:
                        BoxConstraints.tightFor(width: 40.w, height: 40.h),
                    padding: EdgeInsets.zero)
              ])
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (showCallBtn && onClickCallBtn != null)
                  IconButton(
                    icon: Icon(CupertinoIcons.phone_fill,
                        color: Styles.c_0089FF, size: 23.w),
                    tooltip: StrRes.callVoice,
                    onPressed: isMuted ? null : onClickCallBtn,
                    constraints:
                        BoxConstraints.tightFor(width: 40.w, height: 40.h),
                    padding: EdgeInsets.zero,
                  ),
              ]);

  TitleBar.back({
    super.key,
    String? title,
    String? leftTitle,
    TextStyle? titleStyle,
    TextStyle? leftTitleStyle,
    String? result,
    Color? backgroundColor,
    Color? backIconColor,
    this.right,
    this.showUnderline = false,
    Function()? onTap,
  })  : height = NavigationGlassTokens.toolbarHeight,
        backgroundColor = backgroundColor,
        center = Expanded(
            child: (title ?? '').toText
              ..style = (titleStyle ?? Styles.ts_0C1C33_17sp_semibold)
              ..textAlign = TextAlign.center),
        left = GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onTap ?? (() => Get.back(result: result)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ImageRes.backBlack.toImage
                ..width = 24.w
                ..height = 24.h
                ..color = backIconColor ?? Styles.c_0089FF,
              if (null != leftTitle)
                leftTitle.toText
                  ..style = (leftTitleStyle ?? Styles.ts_0C1C33_17sp_semibold),
            ],
          ),
        );

  TitleBar.contacts({
    super.key,
    this.showUnderline = false,
    Function()? onClickAddContacts,
  })  : height = NavigationGlassTokens.toolbarHeight,
        backgroundColor = null,
        center = Spacer(),
        left = StrRes.contacts.toText..style = Styles.ts_0C1C33_20sp_semibold,
        right = Row(
          children: [
            16.horizontalSpace,
            ImageRes.addContacts.toImage
              ..width = 28.w
              ..height = 28.h
              ..onTap = onClickAddContacts,
          ],
        );

  TitleBar.workbench({
    super.key,
    this.showUnderline = false,
  })  : height = NavigationGlassTokens.toolbarHeight,
        backgroundColor = null,
        center = null,
        left = StrRes.workbench.toText..style = Styles.ts_0C1C33_20sp_semibold,
        right = null;

  TitleBar.search({
    super.key,
    String? hintText,
    TextEditingController? controller,
    FocusNode? focusNode,
    bool autofocus = true,
    Function(String)? onSubmitted,
    Function()? onCleared,
    ValueChanged<String>? onChanged,
  })  : height = NavigationGlassTokens.toolbarHeight,
        backgroundColor = null,
        center = Expanded(
          child: Container(
              child: SearchBox(
            enabled: true,
            autofocus: autofocus,
            hintText: hintText,
            controller: controller,
            focusNode: focusNode,
            onSubmitted: onSubmitted,
            onCleared: onCleared,
            onChanged: onChanged,
          )),
        ),
        showUnderline = false,
        right = null,
        left = ImageRes.backBlack.toImage
          ..width = 24.w
          ..height = 24.h
          ..color = Styles.c_0089FF
          ..onTap = (() => Get.back());
}
