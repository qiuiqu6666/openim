import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import '../select_contacts_logic.dart';
import '../widgets/select_contacts_app_bar.dart';
import 'group_list_logic.dart';
import '../../empty/contact_list_placeholder.dart';

class SelectContactsFromGroupPage extends StatelessWidget {
  final logic = Get.find<SelectContactsFromGroupLogic>();
  final selectContactsLogic = Get.find<SelectContactsLogic>();

  SelectContactsFromGroupPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SelectContactsAppBar(title: StrRes.myGroup),
      backgroundColor: Styles.c_F8F9FA,
      body: Column(
        children: [
          if (selectContactsLogic.isMultiModel)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 10.h),
              child: Ink(
                height: 64.h,
                color: Styles.c_FFFFFF,
                child: InkWell(
                  onTap: logic.selectAll,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Row(
                      children: [
                        Obx(() => Padding(
                              padding: EdgeInsets.only(right: 10.w),
                              child: ChatRadio(checked: logic.isSelectAll),
                            )),
                        10.horizontalSpace,
                        StrRes.selectAll.toText..style = Styles.ts_0C1C33_17sp,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Expanded(
              child: Obx(() => logic.allList.isEmpty
                  ? contactListPlaceholder(
                      context,
                      title:
                          Localizations.localeOf(context).languageCode == 'zh'
                              ? '暂无群聊'
                              : 'No groups yet',
                      loading: logic.loading.value,
                      failed: logic.loadFailed.value,
                      onRetry: logic.loadGroups,
                    )
                  : ListView.builder(
                      itemCount: logic.allList.length,
                      itemBuilder: (_, index) =>
                          _buildItemView(logic.allList[index]),
                    ))),
          selectContactsLogic.checkedConfirmView,
        ],
      ),
    );
  }

  Widget _buildItemView(GroupInfo info) {
    Widget buildChild() => Ink(
          height: 64.h,
          color: Styles.c_FFFFFF,
          child: InkWell(
            onTap: selectContactsLogic.onTap(info),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w),
              child: Row(
                children: [
                  if (selectContactsLogic.isMultiModel)
                    Padding(
                      padding: EdgeInsets.only(right: 10.w),
                      child: ChatRadio(
                        checked: selectContactsLogic.isChecked(info),
                        enabled: !selectContactsLogic.isDefaultChecked(info),
                      ),
                    ),
                  AvatarView(
                    url: info.faceURL,
                    text: info.groupName,
                    isGroup: true,
                    isCircle: true,
                  ),
                  10.horizontalSpace,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        (info.groupName ?? '').toText
                          ..style = Styles.ts_0C1C33_17sp
                          ..maxLines = 1
                          ..overflow = TextOverflow.ellipsis,
                        sprintf(StrRes.nPerson, [info.memberCount]).toText
                          ..style = Styles.ts_8E9AB0_14sp,
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
    return selectContactsLogic.isMultiModel ? Obx(buildChild) : buildChild();
  }
}
