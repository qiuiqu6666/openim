import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'edit_my_info_logic.dart';
import '../../contacts/user_profile_panel/set_remark/set_remark_view.dart';

class EditMyInfoPage extends StatelessWidget {
  final logic = Get.find<EditMyInfoLogic>();
  EditMyInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (logic.editAttr == EditAttr.nickname) {
      return Obx(() => SetFriendRemarkPage.editor(
            controller: logic.inputCtrl,
            avatarURL: logic.imLogic.userInfo.value.faceURL,
            avatarName: logic.imLogic.userInfo.value.nickname,
            maxLength: logic.maxLength,
            keyboardType: logic.keyboardType,
            onSave: logic.save,
            onAvatarTap: logic.openPhotoSheet,
          ));
    }
    return Scaffold(
      appBar: TitleBar.back(
        title: logic.title,
        right: StrRes.save.toText
          ..style = Styles.ts_0C1C33_17sp
          ..onTap = logic.save,
      ),
      backgroundColor: Styles.c_FFFFFF,
      body: Column(
        children: [
          22.verticalSpace,
          Container(
            margin: EdgeInsets.symmetric(horizontal: 10.w),
            decoration: BoxDecoration(
              color: Styles.c_E8EAEF,
              borderRadius: BorderRadius.circular(4.r),
            ),
            child: TextField(
              controller: logic.inputCtrl,
              style: Styles.ts_0C1C33_17sp,
              autofocus: true,
              keyboardType: logic.keyboardType,
              inputFormatters: [
                LengthLimitingTextInputFormatter(logic.maxLength)
              ],
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  vertical: 10.h,
                  horizontal: 12.w,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
