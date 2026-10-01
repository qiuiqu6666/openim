import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'set_remark_logic.dart';

class SetFriendRemarkPage extends StatelessWidget {
  SetFriendRemarkPage({super.key, SetFriendRemarkLogic? logic})
      : logic = logic ?? Get.find<SetFriendRemarkLogic>();

  final SetFriendRemarkLogic logic;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_F4F5F7,
        appBar: AppBar(
          backgroundColor: Styles.c_F4F5F7,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: IconButton(
            onPressed: Get.back,
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.arrow_back_ios_new,
                size: 24.w, color: Styles.c_0089FF),
          ),
          actions: [
            TextButton(
              onPressed: logic.save,
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
                  url: logic.avatarURL,
                  text: logic.avatarName,
                  width: 96.w,
                  height: 96.w,
                  textStyle: TextStyle(color: Colors.white, fontSize: 40.sp),
                ),
              ),
              30.verticalSpace,
              TextField(
                controller: logic.inputCtrl,
                maxLength: SetFriendRemarkLogic.maxRemarkLength,
                maxLines: 1,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => logic.save(),
                style: TextStyle(color: Styles.c_0C1C33, fontSize: 16.sp),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Styles.c_FFFFFF,
                  border: _border(),
                  enabledBorder: _border(),
                  focusedBorder: _border(),
                  counterText: '',
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: logic.inputCtrl,
                    builder: (_, value, __) => Padding(
                      padding: EdgeInsets.only(left: 8.w, right: 18.w),
                      child: Center(
                        widthFactor: 1,
                        heightFactor: 1,
                        child: Text(
                          '${value.text.characters.length}/${SetFriendRemarkLogic.maxRemarkLength}',
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
