import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import 'package:pull_to_refresh_new/pull_to_refresh.dart';
import 'package:sprintf/sprintf.dart';

import 'group_member_list_logic.dart';
import '../../../contacts/presence_label.dart';
import 'package:visibility_detector/visibility_detector.dart';

class GroupMemberListPage extends StatelessWidget {
  final logic = Get.find<GroupMemberListLogic>(
      tag: (Get.arguments['opType'] as GroupMemberOpType).name);

  GroupMemberListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() => Scaffold(
          appBar: TitleBar.back(
            title: logic.opType == GroupMemberOpType.del
                ? StrRes.removeGroupMember
                : logic.groupInfo.memberCount == null
                    ? StrRes.groupMember
                    : 'groupMemberPageTitle'
                        .trParams({'count': '${logic.groupInfo.memberCount}'}),
            backIconColor: Styles.c_0089FF,
            right: SizedBox(width: 24.w),
          ),
          backgroundColor: Styles.c_FFFFFF,
          body: Column(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(10.r),
                    child: SearchBox(
                      height: 40.h,
                      hintText: 'groupMemberSearchHint'.tr,
                      backgroundColor: Styles.c_F0F2F6,
                      enabled: true,
                      controller: logic.searchController,
                      onChanged: logic.searchChanged,
                      onCleared: () => logic.searchChanged(''),
                      onSubmitted: (_) => logic.searchMembers(),
                    )),
              ),
              if (logic.searching.value) const LinearProgressIndicator(),
              if (logic.searchFailed.value)
                TextButton(
                    onPressed: () => logic.searchMembers(),
                    child: Text('chatSearchRetry'.tr)),
              if (logic.query.isNotEmpty &&
                  !logic.searching.value &&
                  !logic.searchFailed.value &&
                  logic.visibleMembers.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('chatSearchEmpty'.tr,
                        style: Styles.ts_8E9AB0_14sp)),
              if (logic.opType == GroupMemberOpType.at && logic.isOwnerOrAdmin)
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: logic.selectEveryone,
                  child: Container(
                    height: 64.h,
                    color: Styles.c_FFFFFF,
                    margin: EdgeInsets.symmetric(vertical: 10.h),
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        AvatarView(
                          width: 44.w,
                          height: 44.h,
                          text: '@',
                          textStyle: Styles.ts_FFFFFF_21sp,
                        ),
                        10.horizontalSpace,
                        StrRes.everyone.toText..style = Styles.ts_0C1C33_17sp,
                      ],
                    ),
                  ),
                ),
              Flexible(
                child: SmartRefresher(
                  controller: logic.controller,
                  onLoading: logic.onLoad,
                  enablePullDown: false,
                  enablePullUp: logic.query.isEmpty,
                  header: IMViews.buildHeader(),
                  footer: IMViews.buildFooter(),
                  child: ListView.separated(
                    itemCount: logic.visibleMembers.length,
                    separatorBuilder: (_, __) => Padding(
                        padding: EdgeInsets.only(left: 58.w),
                        child: Divider(
                            height: 1, thickness: 0.5, color: Styles.c_E8EAEF)),
                    padding: EdgeInsets.only(bottom: 16.h),
                    itemBuilder: (_, index) {
                      final member = logic.visibleMembers[index];
                      return VisibilityDetector(
                        key: ValueKey('group-member-presence-${member.userID}'),
                        onVisibilityChanged: (info) {
                          if (member.userID != null)
                            logic.setPresenceVisible(
                                member.userID!, info.visibleFraction > 0);
                        },
                        child: Obx(() => _buildItemView(member)),
                      );
                    },
                  ),
                ),
              ),
              if (logic.query.isNotEmpty &&
                  logic.searchMore.value &&
                  !logic.searchFailed.value)
                TextButton(
                    onPressed: logic.searching.value
                        ? null
                        : () => logic.searchMembers(next: true),
                    child: Text('chatSearchMore'.tr)),
              if (logic.isMultiSelMode) _buildCheckedConfirmView(),
            ],
          ),
        ));
  }

  Widget _buildItemView(GroupMembersInfo membersInfo) => logic
          .hiddenMember(membersInfo)
      ? const SizedBox()
      : GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => logic.clickMember(membersInfo),
          child: Container(
            constraints: BoxConstraints(minHeight: 56.h),
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            color: Styles.c_FFFFFF,
            child: Row(
              children: [
                if (logic.isMultiSelMode)
                  Padding(
                    padding: EdgeInsets.only(right: 15.w),
                    child: ChatRadio(checked: logic.isChecked(membersInfo)),
                  ),
                AvatarView(
                  width: 40.w,
                  height: 40.w,
                  url: membersInfo.faceURL,
                  text: membersInfo.nickname,
                ),
                10.horizontalSpace,
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(membersInfo.nickname ?? '',
                            style: Styles.ts_0C1C33_17sp,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        if (logic.presence.users[membersInfo.userID]
                            case final presence?) ...[
                          4.verticalSpace,
                          PresenceLabel(presence: presence),
                        ],
                      ]),
                ),
                if (membersInfo.roleLevel == GroupRoleLevel.owner ||
                    membersInfo.roleLevel == GroupRoleLevel.admin) ...[
                  8.horizontalSpace,
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
                    decoration: BoxDecoration(
                      color: (membersInfo.roleLevel == GroupRoleLevel.owner
                              ? Styles.c_0089FF
                              : const Color(0xFFBE790A))
                          .withValues(alpha: Styles.isDark ? .18 : .07),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                        membersInfo.roleLevel == GroupRoleLevel.owner
                            ? StrRes.groupOwner
                            : StrRes.groupAdmin,
                        style: Styles.ts_0089FF_12sp.copyWith(
                            color: membersInfo.roleLevel == GroupRoleLevel.owner
                                ? Styles.c_0089FF
                                : Styles.isDark
                                    ? const Color(0xFFF0B451)
                                    : const Color(0xFFBE790A))),
                  ),
                ],
              ],
            ),
          ),
        );

  Widget _buildCheckedConfirmView() => Container(
        height: 66.h,
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          boxShadow: [
            BoxShadow(
              offset: Offset(0, -1.h),
              blurRadius: 4.r,
              spreadRadius: 1.r,
              color: Styles.c_000000_opacity4,
            ),
          ],
        ),
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => Get.bottomSheet(
                  SelectedMemberListView(),
                  isScrollControlled: true,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        sprintf(StrRes.selectedPeopleCount,
                            [logic.checkedList.length]).toText
                          ..style = Styles.ts_0089FF_14sp,
                        ImageRes.expandUpArrow.toImage
                          ..width = 24.w
                          ..height = 24.h,
                      ],
                    ),
                    if (logic.checkedList.isNotEmpty) 4.verticalSpace,
                    logic.checkedList
                        .map((e) => e.nickname ?? '')
                        .join('、')
                        .toText
                      ..style = Styles.ts_8E9AB0_14sp
                      ..maxLines = 1
                      ..overflow = TextOverflow.ellipsis,
                  ],
                ),
              ),
            ),
            Button(
              height: 40.h,
              padding: EdgeInsets.symmetric(horizontal: 14.w),
              text: sprintf(StrRes.confirmSelectedPeople, [
                logic.checkedList.length,
                logic.maxLength,
              ]),
              textStyle: Styles.ts_FFFFFF_14sp,
              onTap: logic.confirmSelectedMember,
            ),
          ],
        ),
      );
}

class SelectedMemberListView extends StatelessWidget {
  SelectedMemberListView({Key? key}) : super(key: key);
  final logic = Get.find<GroupMemberListLogic>(
      tag: (Get.arguments['opType'] as GroupMemberOpType).name);

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: 548.h),
      decoration: BoxDecoration(
        color: Styles.c_FFFFFF,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(6.r),
          topRight: Radius.circular(6.r),
        ),
      ),
      child: Obx(() => Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    bottom: BorderSide(color: Styles.c_E8EAEF, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    sprintf(StrRes.selectedPeopleCount,
                        [logic.checkedList.length]).toText
                      ..style = Styles.ts_0C1C33_17sp_medium,
                    const Spacer(),
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => Get.back(),
                      child: Container(
                        height: 52.h,
                        alignment: Alignment.center,
                        child: StrRes.confirm.toText
                          ..style = Styles.ts_0089FF_17sp,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: logic.checkedList.length,
                  shrinkWrap: true,
                  itemBuilder: (_, index) =>
                      _buildItemView(logic.checkedList[index]),
                ),
              ),
            ],
          )),
    );
  }

  Widget _buildItemView(GroupMembersInfo membersInfo) => Container(
        height: 64.h,
        padding: EdgeInsets.symmetric(horizontal: 16.w),
        color: Styles.c_FFFFFF,
        child: Row(
          children: [
            AvatarView(
              url: membersInfo.faceURL,
              text: membersInfo.nickname,
            ),
            10.horizontalSpace,
            Expanded(
              child: (membersInfo.nickname ?? '').toText
                ..style = Styles.ts_0C1C33_17sp
                ..maxLines = 1
                ..overflow = TextOverflow.ellipsis,
            ),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => logic.removeSelectedMember(membersInfo),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 13.w, vertical: 4.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2.r),
                  border: Border.all(
                    color: Styles.c_E8EAEF,
                    width: 1,
                  ),
                ),
                child: StrRes.remove.toText..style = Styles.ts_0089FF_17sp,
              ),
            ),
          ],
        ),
      );
}
