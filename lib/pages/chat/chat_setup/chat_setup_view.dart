import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'chat_setup_logic.dart';

class ChatSetupPage extends StatelessWidget {
  final logic = Get.find<ChatSetupLogic>();

  ChatSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: Text('chatSettingsTitle'.tr, style: Styles.ts_0C1C33_17sp),
        centerTitle: true,
        leading: IconButton(
            onPressed: () => Get.back(),
            icon:
                Icon(Icons.arrow_back_ios_new_rounded, color: Styles.c_0089FF)),
      ),
      backgroundColor: Styles.c_F8F9FA,
      body: SingleChildScrollView(
        child: Obx(() => Column(
              children: [
                _buildBaseInfoView(),
                _buildItemView(
                    text: 'findChatContent'.tr,
                    showRightArrow: true,
                    isTopRadius: true,
                    isBottomRadius: true,
                    onTap: logic.searchHistory),
                12.verticalSpace,
                _buildItemView(
                    text: StrRes.topChat,
                    showSwitchButton: true,
                    isTopRadius: true,
                    switchOn: logic.isPinned,
                    onChanged: logic.updating.value ? null : logic.setPinned),
                _buildItemView(
                    text: StrRes.notDisturbMode,
                    showSwitchButton: true,
                    isBottomRadius: true,
                    switchOn: logic.isMuted,
                    onChanged: logic.updating.value ? null : logic.setMuted),
                12.verticalSpace,
                _buildItemView(
                    text: 'currentChatBackground'.tr,
                    showRightArrow: true,
                    isTopRadius: true,
                    isBottomRadius: true,
                    onTap: logic.setBackground),
                12.verticalSpace,
                _buildItemView(
                    text: StrRes.clearChatHistory,
                    showRightArrow: true,
                    isTopRadius: true,
                    isBottomRadius: true,
                    onTap: logic.clearHistory),
                24.verticalSpace,
              ],
            )),
      ),
    );
  }

  Widget _buildBaseInfoView() => Container(
        margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 20.h),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(14.r),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          InkWell(
              onTap: logic.viewUserInfo,
              child: SizedBox(
                  height: 48.h,
                  child: Row(children: [
                    Expanded(
                        child: Text('chatMembersTitle'.tr,
                            style: Styles.ts_0C1C33_17sp)),
                    Text('oneChatMember'.tr, style: Styles.ts_8E9AB0_14sp),
                    Icon(Icons.chevron_right_rounded, color: Styles.c_8E9AB0),
                  ]))),
          Row(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: logic.viewUserInfo,
                child: SizedBox(
                  width: 76.w,
                  child: Column(
                    children: [
                      AvatarView(
                        width: 44.w,
                        height: 44.h,
                        text: logic.conversationInfo.value.showName,
                        url: logic.conversationInfo.value.faceURL,
                        onTap: logic.viewUserInfo,
                      ),
                      8.verticalSpace,
                      (logic.conversationInfo.value.showName ?? '').toText
                        ..style = Styles.ts_8E9AB0_14sp
                        ..maxLines = 1
                        ..overflow = TextOverflow.ellipsis,
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 76.w,
                child: Column(
                  children: [
                    ImageRes.addFriendTobeGroup.toImage
                      ..width = 44.w
                      ..height = 44.h
                      ..onTap = logic.createGroup,
                    8.verticalSpace,
                    'addChatMember'.tr.toText
                      ..style = Styles.ts_8E9AB0_14sp
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis,
                  ],
                ),
              ),
            ],
          ),
        ]),
      );

  Widget _buildItemView({
    required String text,
    String? hintText,
    TextStyle? textStyle,
    String? value,
    bool switchOn = false,
    bool isTopRadius = false,
    bool isBottomRadius = false,
    bool showRightArrow = false,
    bool showSwitchButton = false,
    ValueChanged<bool>? onChanged,
    Function()? onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: Container(
          height: hintText == null ? 56.h : 68.h,
          margin: EdgeInsets.symmetric(horizontal: 12.w),
          padding: EdgeInsets.symmetric(horizontal: 16.w),
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(isTopRadius ? 14.r : 0),
              topLeft: Radius.circular(isTopRadius ? 14.r : 0),
              bottomLeft: Radius.circular(isBottomRadius ? 14.r : 0),
              bottomRight: Radius.circular(isBottomRadius ? 14.r : 0),
            ),
          ),
          child: Row(
            children: [
              null != hintText
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        text.toText..style = textStyle ?? Styles.ts_0C1C33_17sp,
                        hintText.toText..style = Styles.ts_8E9AB0_14sp,
                      ],
                    )
                  : (text.toText..style = textStyle ?? Styles.ts_0C1C33_17sp),
              const Spacer(),
              if (null != value) value.toText..style = Styles.ts_8E9AB0_14sp,
              if (showSwitchButton)
                CupertinoSwitch(
                  value: switchOn,
                  activeColor: Styles.c_0089FF,
                  onChanged: onChanged,
                ),
              if (showRightArrow)
                ImageRes.rightArrow.toImage
                  ..width = 24.w
                  ..height = 24.h,
            ],
          ),
        ),
      );
}
