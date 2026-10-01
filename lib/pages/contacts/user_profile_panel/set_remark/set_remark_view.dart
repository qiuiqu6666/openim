import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'set_remark_logic.dart';

class SetFriendRemarkPage extends StatelessWidget {
  factory SetFriendRemarkPage({Key? key, SetFriendRemarkLogic? logic}) {
    final editor = logic ?? Get.find<SetFriendRemarkLogic>();
    return SetFriendRemarkPage.editor(
      key: key,
      controller: editor.inputCtrl,
      avatarURL: editor.avatarURL,
      avatarName: editor.avatarName,
      maxLength: SetFriendRemarkLogic.maxRemarkLength,
      onSave: editor.save,
    );
  }

  const SetFriendRemarkPage.editor({
    super.key,
    required this.controller,
    required this.onSave,
    required this.maxLength,
    this.avatarURL,
    this.avatarName,
    this.keyboardType,
    this.onAvatarTap,
  });

  final TextEditingController controller;
  final VoidCallback onSave;
  final int maxLength;
  final String? avatarURL;
  final String? avatarName;
  final TextInputType? keyboardType;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_F4F5F7,
        appBar: GlassAppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: Get.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new,
                size: 24.w, color: Styles.c_0089FF),
          ),
          actions: [
            TextButton(
              onPressed: onSave,
              child: Text(StrRes.determine,
                  style: TextStyle(color: Styles.c_0089FF, fontSize: 16.sp)),
            ),
            6.horizontalSpace,
          ],
        ),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(14.w, 24.h, 14.w, 24.h),
            child: Column(children: [
              Center(
                child: AvatarView(
                  onTap: onAvatarTap,
                  url: avatarURL,
                  text: avatarName,
                  width: 96.w,
                  height: 96.w,
                  textStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimary,
                      fontSize: 40.sp),
                ),
              ),
              30.verticalSpace,
              TextField(
                controller: controller,
                maxLength: maxLength,
                keyboardType: keyboardType,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSave(),
                style: TextStyle(color: Styles.c_0C1C33, fontSize: 16.sp),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Styles.c_FFFFFF,
                  border: _border(),
                  enabledBorder: _border(),
                  focusedBorder: _border(),
                  counterText: '',
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (_, value, __) => Padding(
                      padding: EdgeInsets.only(left: 8.w, right: 18.w),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Text(
                          '${value.text.characters.length}/$maxLength',
                          style: Styles.ts_8E9AB0_13sp,
                        ),
                      ),
                    ),
                  ),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 18.w, vertical: 13.h),
                ),
              ),
            ]),
          ),
        ),
      );

  OutlineInputBorder _border() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: BorderSide.none,
      );
}
