import 'package:flutter/material.dart';
import '../../../group_features/identity/group_name_label.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:sprintf/sprintf.dart';

import '../select_contacts_logic.dart';
import '../widgets/select_contacts_app_bar.dart';
import '../contact_card/contact_card_picker_tokens.dart';
import 'group_list_logic.dart';
import '../../empty/contact_list_placeholder.dart';

class SelectContactsFromGroupPage extends StatelessWidget {
  final SelectContactsFromGroupLogic logic;
  final SelectContactsLogic selectContactsLogic;
  final String? title;

  SelectContactsFromGroupPage(
      {super.key,
      this.title,
      SelectContactsFromGroupLogic? logic,
      SelectContactsLogic? selection})
      : logic = logic ?? Get.find<SelectContactsFromGroupLogic>(),
        selectContactsLogic = selection ?? Get.find<SelectContactsLogic>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SelectContactsAppBar(title: title ?? StrRes.myGroup),
      backgroundColor: ContactCardPickerTokens.pageBackground(context),
      body: Column(
        children: [
          SearchBox(
            key: const ValueKey('select-groups-search'),
            controller: logic.searchController,
            enabled: true,
            height: ContactCardPickerTokens.searchHeight(context),
            margin: ContactCardPickerTokens.searchPadding,
            borderRadius:
                BorderRadius.circular(ContactCardPickerTokens.searchRadius),
            surfaceColor: Styles.c_FFFFFF,
            backgroundColor: Styles.c_F4F5F7,
            textStyle: ContactCardPickerTokens.searchStyle(context),
            hintStyle: ContactCardPickerTokens.searchStyle(context, hint: true),
            searchIconColor: ContactCardPickerTokens.secondary(context),
            onChanged: logic.searchGroups,
            onCleared: () => logic.searchGroups(''),
            onSubmitted: (value) {
              logic.searchGroups(value);
              FocusScope.of(context).unfocus();
            },
          ),
          if (selectContactsLogic.isMultiModel)
            Ink(
              color: Styles.c_FFFFFF,
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
          Expanded(child: Obx(() {
            final groups = logic.visibleGroups;
            return groups.isEmpty
                ? contactListPlaceholder(
                    context,
                    title: Localizations.localeOf(context).languageCode == 'zh'
                        ? (logic.searchQuery.isEmpty ? '暂无群聊' : '未找到相关群聊')
                        : (logic.searchQuery.isEmpty
                            ? 'No groups yet'
                            : 'No matching groups'),
                    loading: logic.loading.value,
                    failed: logic.loadFailed.value,
                    onRetry: logic.loadGroups,
                  )
                : ListView.builder(
                    key: ValueKey(logic.searchQuery.value),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    itemCount: groups.length,
                    itemBuilder: (_, index) =>
                        _buildItemView(context, groups[index]),
                  );
          })),
          selectContactsLogic.checkedConfirmView,
        ],
      ),
    );
  }

  Widget _buildItemView(BuildContext context, GroupInfo info) {
    Widget buildChild() => Material(
          color: ContactCardPickerTokens.rowBackground(context),
          child: InkWell(
            key: ValueKey('select-group-${info.groupID}'),
            onTap: selectContactsLogic.onTap(info),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 64.h),
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 16.w,
                    vertical: ContactCardPickerTokens.verticalPadding),
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
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GroupNameLabel(
                            name: info.groupName ?? '',
                            ex: info.ex,
                            style: ContactCardPickerTokens.titleStyle(context),
                          ),
                          sprintf(StrRes.nPerson, [info.memberCount]).toText
                            ..style =
                                ContactCardPickerTokens.subtitleStyle(context),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
    return selectContactsLogic.isMultiModel ? Obx(buildChild) : buildChild();
  }
}
