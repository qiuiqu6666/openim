import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'language_setup_logic.dart';

class LanguageSetupPage extends StatelessWidget {
  final logic = Get.find<LanguageSetupLogic>();

  LanguageSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(title: StrRes.languageSetup),
      backgroundColor: Styles.c_F8F9FA,
      body: Obx(() => ListView(
            children: [
              12.verticalSpace,
              _buildItemView(
                label: StrRes.followSystem,
                isChecked: logic.selectedLanguage.value == 0,
                onTap: () => logic.switchLanguage(0),
                isTopRadius: true,
              ),
              Container(
                margin: EdgeInsets.only(left: 26.w, right: 10.w),
                color: Styles.c_E8EAEF,
                height: .5,
              ),
              _buildItemView(
                label: StrRes.chinese,
                isChecked: logic.selectedLanguage.value == 1,
                onTap: () => logic.switchLanguage(1),
              ),
              Container(
                margin: EdgeInsets.only(left: 26.w, right: 10.w),
                color: Styles.c_E8EAEF,
                height: .5,
              ),
              _buildItemView(
                label: StrRes.traditionalChinese,
                isChecked: logic.selectedLanguage.value == 3,
                onTap: () => logic.switchLanguage(3),
              ),
              Container(
                margin: EdgeInsets.only(left: 26.w, right: 10.w),
                color: Styles.c_E8EAEF,
                height: .5,
              ),
              _buildItemView(
                label: StrRes.english,
                isChecked: logic.selectedLanguage.value == 2,
                onTap: () => logic.switchLanguage(2),
                isBottomRadius: true,
              ),
            ],
          )),
    );
  }

  Widget _buildItemView({
    required String label,
    bool isChecked = false,
    bool isTopRadius = false,
    bool isBottomRadius = false,
    Function()? onTap,
  }) =>
      Container(
        margin: EdgeInsets.symmetric(horizontal: 10.w),
        child: Semantics(
          selected: isChecked,
          inMutuallyExclusiveGroup: true,
          child: Ink(
            decoration: BoxDecoration(
              color: Styles.c_FFFFFF,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isTopRadius ? 6.r : 0),
                topRight: Radius.circular(isTopRadius ? 6.r : 0),
                bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
                bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isTopRadius ? 6.r : 0),
                topRight: Radius.circular(isTopRadius ? 6.r : 0),
                bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
                bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: 60.h < 48 ? 48 : 60.h),
                child: Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  child: Row(
                    children: [
                      Expanded(
                          child: label.toText..style = Styles.ts_0C1C33_17sp),
                      if (isChecked)
                        ImageRes.checked.toImage
                          ..width = 24.w
                          ..height = 24.h,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
