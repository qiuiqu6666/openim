import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'account_setup_logic.dart';

class AccountSetupPage extends StatelessWidget {
  final logic = Get.find<AccountSetupLogic>();

  AccountSetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TitleBar.back(
        title: StrRes.accountSetup,
      ),
      backgroundColor: Styles.c_F8F9FA,
      body: Obx(() => SingleChildScrollView(
            child: Column(
              children: [
                10.verticalSpace,
                _buildItemView(
                    label: 'sdkGlobalMute'.tr,
                    switchOn:
                        logic.imLogic.userInfo.value.globalRecvMsgOpt == 2,
                    showSwitchButton: true,
                    onChanged: logic.globalMuteBusy.value
                        ? null
                        : logic.setGlobalMute),
                _buildItemView(
                  label: 'showLastSeen'.tr,
                  switchOn: logic.presenceVisibility.showLastSeen.value,
                  showSwitchButton: true,
                  isTopRadius: true,
                  isBottomRadius: true,
                  onChanged: logic.presenceVisibility.ready.value &&
                          !logic.presenceVisibility.busy.value
                      ? logic.presenceVisibility.setVisible
                      : null,
                ),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 26.w, vertical: 8.h),
                  child:
                      Text('showLastSeenHint'.tr, style: Styles.ts_8E9AB0_12sp),
                ),
                if (logic.presenceVisibility.busy.value)
                  const LinearProgressIndicator(),
                if (logic.presenceVisibility.failed.value)
                  TextButton(
                      onPressed: logic.presenceVisibility.refresh,
                      child: Text('presenceVisibilityRetry'.tr)),
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 26.w, vertical: 12.h),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('friendAddSettings'.tr,
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                ),
                if (logic.friendSettingsFailed.value)
                  TextButton(
                    onPressed: logic.refreshFriendSettings,
                    child: Text('friendAddSettingsRetry'.tr),
                  ),
                if (logic.friendSettingsReady.value) ...[
                  _buildItemView(
                    label: 'allowAddFriend'.tr,
                    switchOn: logic.allowAddFriend.value == 1,
                    showSwitchButton: true,
                    isTopRadius: true,
                    onChanged: logic.friendSettingsBusy.value
                        ? null
                        : (value) =>
                            logic.setFriendPermission('allowAddFriend', value),
                  ),
                  for (final entry in const [
                    ('allowAddByUserID', 'allowAddByUserID'),
                    ('allowAddByPhone', 'allowAddByPhone'),
                    ('allowAddByEmail', 'allowAddByEmail'),
                    ('allowAddByQRCode', 'allowAddByQRCode'),
                    ('allowAddByGroup', 'allowAddByGroup'),
                    ('allowAddByCard', 'allowAddByCard'),
                  ])
                    _buildItemView(
                      label: entry.$2.tr,
                      switchOn: logic.friendPermissions[entry.$1] != 2,
                      showSwitchButton: true,
                      isBottomRadius: entry.$1 == 'allowAddByCard',
                      onChanged: logic.friendSettingsBusy.value ||
                              logic.allowAddFriend.value != 1
                          ? null
                          : (value) =>
                              logic.setFriendPermission(entry.$1, value),
                    ),
                  Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 26.w, vertical: 8.h),
                    child: Text('friendAddSettingsHint'.tr,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                ],
                _buildItemView(
                  label: StrRes.blacklist,
                  onTap: logic.blacklist,
                  showRightArrow: true,
                ),
                _buildItemView(
                  label: StrRes.languageSetup,
                  value: logic.curLanguage.value,
                  onTap: logic.languageSetting,
                  showRightArrow: true,
                  isBottomRadius: true,
                ),
              ],
            ),
          )),
    );
  }

  Widget _buildItemView({
    required String label,
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
      Container(
        margin: EdgeInsets.symmetric(horizontal: 10.w),
        child: Ink(
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(isTopRadius ? 6.r : 0),
              topLeft: Radius.circular(isTopRadius ? 6.r : 0),
              bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
              bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(isTopRadius ? 6.r : 0),
              topLeft: Radius.circular(isTopRadius ? 6.r : 0),
              bottomLeft: Radius.circular(isBottomRadius ? 6.r : 0),
              bottomRight: Radius.circular(isBottomRadius ? 6.r : 0),
            ),
            child: Container(
              height: 46.h,
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  Expanded(
                      child: Text(label,
                          style: textStyle ?? Styles.ts_0C1C33_17sp)),
                  if (showSwitchButton)
                    CupertinoSwitch(
                      value: switchOn,
                      activeTrackColor: Styles.c_0089FF,
                      onChanged: onChanged,
                    ),
                  if (showRightArrow)
                    ImageRes.rightArrow.toImage
                      ..width = 24.w
                      ..height = 24.h,
                ],
              ),
            ),
          ),
        ),
      );
}
