import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'group_setup_logic.dart';
import 'group_announcement_page.dart';
import '../group/announcements/group_announcement_banner.dart';

class GroupSetupPage extends StatelessWidget {
  final GroupSetupLogic logic;

  GroupSetupPage({super.key, GroupSetupLogic? logic})
      : logic = logic ?? Get.find<GroupSetupLogic>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        toolbarHeight: kToolbarHeight,
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: Styles.c_F8F9FA,
        surfaceTintColor: Styles.c_F8F9FA,
        elevation: 0,
        leading: IconButton(
          onPressed: Get.back,
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(CupertinoIcons.back, size: 24.w, color: Styles.c_0089FF),
        ),
        title: Text(StrRes.groupChat, style: Styles.ts_0C1C33_17sp_semibold),
      ),
      backgroundColor: Styles.c_F8F9FA,
      body: Obx(() => SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (logic.isJoinedGroup.value) _groupHeaderCard(),
                if (logic.isJoinedGroup.value) _membersCard(),
                if (logic.isJoinedGroup.value) _detailsCard(),
                if (logic.isJoinedGroup.value)
                  _section([
                    _settingRow('findChatContent'.tr,
                        onTap: logic.searchHistory)
                  ]),
                if (logic.isJoinedGroup.value)
                  _section([
                    _settingRow('groupMuteLabel'.tr,
                        trailing: CupertinoSwitch(
                          value: logic.isNotDisturb,
                          activeTrackColor: Styles.c_0089FF,
                          onChanged:
                              logic.updating.value ? null : logic.setMuted,
                        )),
                    _settingRow('groupPinLabel'.tr,
                        trailing: CupertinoSwitch(
                          value: logic.isPinned,
                          activeTrackColor: Styles.c_0089FF,
                          onChanged:
                              logic.updating.value ? null : logic.setPinned,
                        )),
                  ]),
                if (logic.isJoinedGroup.value)
                  _section([
                    _settingRow('groupReport'.tr,
                        onTap: () =>
                            IMViews.showToast('groupReportUnavailable'.tr))
                  ]),
                if (logic.isOwner || logic.isAdmin)
                  _section([
                    _settingRow(StrRes.groupManage, onTap: logic.groupManage)
                  ]),
                if (!logic.isOwner)
                  _section([
                    _settingRow(
                        logic.isJoinedGroup.value
                            ? StrRes.exitGroup
                            : StrRes.delete,
                        color: Styles.c_FF381F,
                        onTap: logic.quitGroup)
                  ]),
                if (logic.isOwner)
                  _section([
                    _settingRow(StrRes.dismissGroup,
                        color: Styles.c_FF381F, onTap: logic.quitGroup)
                  ]),
                40.verticalSpace,
              ],
            ),
          )),
    );
  }

  String get _displayGroupID {
    final id = logic.groupInfo.value.groupID;
    return id.startsWith('@') ? id : '@$id';
  }

  Widget _section(List<Widget> rows) => Container(
        margin: EdgeInsets.fromLTRB(8.w, 0, 8.w, 10.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Divider(height: 1, color: Styles.c_E8EAEF),
            rows[i],
          ],
        ]),
      );

  Widget _settingRow(String label,
          {String? value,
          Widget? trailing,
          VoidCallback? onTap,
          bool showArrow = true,
          Color? color}) =>
      InkWell(
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          height: 56.h,
          child: Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: color ?? Styles.c_0C1C33, fontSize: 16.sp)),
            ),
            if (value != null)
              Flexible(
                fit: FlexFit.tight,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: Styles.c_8E9AB0, fontSize: 14.sp)),
                ),
              ),
            if (trailing != null) trailing,
            if (onTap != null && showArrow) ...[
              6.horizontalSpace,
              Icon(Icons.chevron_right_rounded,
                  size: 22.w, color: Styles.c_8E9AB0),
            ],
          ]),
        ),
      );

  Widget _groupHeaderCard() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: logic.isOwnerOrAdmin
            ? () => logic.modifyGroupName(logic.groupInfo.value.faceURL)
            : null,
        child: Container(
          margin: EdgeInsets.fromLTRB(8.w, 0, 8.w, 10.h),
          padding: EdgeInsets.all(14.w),
          decoration: BoxDecoration(
            color: Styles.c_FFFFFF,
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Row(children: [
            AvatarView(
              width: 48.w,
              height: 48.w,
              url: logic.groupInfo.value.faceURL,
              file: logic.avatar.value,
              text: logic.groupInfo.value.groupName,
              isGroup: true,
              isCircle: true,
              enabledPreview: !logic.isOwnerOrAdmin,
              onTap: logic.isOwnerOrAdmin
                  ? () => logic.modifyGroupName(logic.groupInfo.value.faceURL)
                  : null,
            ),
            12.horizontalSpace,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: logic.isOwnerOrAdmin
                        ? () =>
                            logic.modifyGroupName(logic.groupInfo.value.faceURL)
                        : null,
                    child: Text(logic.groupInfo.value.groupName ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Styles.ts_0C1C33_17sp_semibold),
                  ),
                  5.verticalSpace,
                  InkWell(
                    onTap: logic.copyGroupID,
                    child: Row(children: [
                      Flexible(
                        child: Text(_displayGroupID,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Styles.ts_8E9AB0_14sp),
                      ),
                      4.horizontalSpace,
                      Icon(Icons.copy_outlined,
                          size: 14.w, color: Styles.c_8E9AB0),
                    ]),
                  ),
                ],
              ),
            ),
            if (logic.isOwnerOrAdmin) ...[
              8.horizontalSpace,
              Icon(Icons.chevron_right_rounded,
                  size: 22.w, color: Styles.c_8E9AB0),
            ],
          ]),
        ),
      );

  Widget _membersCard() => Container(
        margin: EdgeInsets.fromLTRB(8.w, 0, 8.w, 10.h),
        padding: EdgeInsets.fromLTRB(14.w, 6.h, 14.w, 14.h),
        decoration: BoxDecoration(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(12.r),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _settingRow(StrRes.groupMember,
              value: 'groupMemberTotal'.trParams({
                'count':
                    '${logic.groupInfo.value.memberCount ?? logic.memberList.length}'
              }),
              onTap: logic.viewGroupMembers),
          4.verticalSpace,
          SizedBox(
            key: const ValueKey('group-member-preview-row'),
            height: 78.h,
            child: LayoutBuilder(builder: (context, constraints) {
              final memberWidth = constraints.maxWidth / 7;
              return Row(
                children: [
                  Expanded(
                    child: Obx(() => _memberPreviewContent(memberWidth)),
                  ),
                  if (logic.isJoinedGroup.value || logic.isOwnerOrAdmin)
                    _memberAddButton(memberWidth),
                  if (logic.isOwnerOrAdmin) _memberRemoveButton(memberWidth),
                ],
              );
            }),
          ),
        ]),
      );

  Widget _memberPreviewContent(double memberWidth) {
    if (logic.memberList.isNotEmpty) {
      return ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final member in logic.memberList.take(6))
            _memberPreview(member, memberWidth),
        ],
      );
    }
    if (logic.membersLoading.value) {
      return Semantics(
        label: '正在加载群成员',
        child: ExcludeSemantics(
          child: Row(
            children: List.generate(
              6,
              (index) => Expanded(
                key: ValueKey('group-member-placeholder-$index'),
                child: Column(children: [
                  CircleAvatar(
                    radius: memberWidth * 0.36,
                    backgroundColor: Styles.c_E8EAEF,
                  ),
                  6.verticalSpace,
                  Container(
                    width: memberWidth * 0.72,
                    height: 6.h,
                    decoration: BoxDecoration(
                      color: Styles.c_E8EAEF,
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    return InkWell(
      key: const ValueKey('group-member-preview-retry'),
      onTap: logic.getGroupMembers,
      child: Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 6.w),
          child: Text(
            logic.membersFailed.value ? '群成员加载失败，点击重试' : '暂未获取到群成员，点击重试',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Styles.ts_8E9AB0_12sp,
          ),
        ),
      ),
    );
  }

  Widget _memberPreview(GroupMembersInfo member, double memberWidth) {
    final isOwner = member.userID == logic.groupInfo.value.ownerUserID;
    final isAdmin = member.roleLevel == GroupRoleLevel.admin;
    return SizedBox(
      width: memberWidth,
      child: InkWell(
        onTap: () => logic.viewMemberInfo(member),
        child: Column(children: [
          AvatarView(
              width: memberWidth * 0.72,
              height: memberWidth * 0.72,
              url: member.faceURL,
              text: member.nickname,
              isCircle: true),
          2.verticalSpace,
          if (isOwner || isAdmin)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 4.w),
              decoration: BoxDecoration(
                color: isOwner ? Styles.c_0089FF : const Color(0xFFFF9800),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(isOwner ? StrRes.groupOwner : 'groupAdmin'.tr,
                  style: TextStyle(color: Colors.white, fontSize: 9.sp)),
            ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: memberWidth * 0.05),
              child: Text(member.nickname ?? '',
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: Styles.ts_8E9AB0_10sp),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _memberAddButton(double memberWidth) => SizedBox(
        width: memberWidth,
        child: InkWell(
          onTap: logic.addMember,
          child: Column(children: [
            CircleAvatar(
                radius: memberWidth * 0.36,
                backgroundColor: Styles.c_E8EAEF,
                child: Icon(Icons.add, color: Styles.c_8E9AB0)),
            6.verticalSpace,
            Text('addChatMember'.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Styles.ts_8E9AB0_10sp),
          ]),
        ),
      );

  Widget _memberRemoveButton(double memberWidth) => SizedBox(
        width: memberWidth,
        child: InkWell(
          onTap: logic.removeMember,
          child: Column(children: [
            CircleAvatar(
                radius: memberWidth * 0.36,
                backgroundColor: Styles.c_E8EAEF,
                child: Icon(Icons.remove, color: Styles.c_8E9AB0)),
            6.verticalSpace,
            Text(StrRes.delMember,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Styles.ts_8E9AB0_10sp),
          ]),
        ),
      );

  Widget _detailsCard() => _section([
        _settingRow('groupIdShort'.tr,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 155.w),
                  child: Text(_displayGroupID,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(color: Styles.c_0089FF, fontSize: 14.sp))),
              8.horizontalSpace,
              Icon(Icons.qr_code_2, size: 24.w, color: Styles.c_0C1C33),
            ]),
            onTap: logic.viewGroupQrcode,
            showArrow: false),
        _settingRow('groupAnnouncement'.tr,
            value: logic.groupInfo.value.notification?.isNotEmpty == true
                ? logic.groupInfo.value.notification
                : 'groupNoAnnouncement'.tr,
            showArrow: logic.isOwnerOrAdmin ||
                (logic.groupInfo.value.notification?.trim().isNotEmpty ??
                    false),
            onTap: logic.isOwnerOrAdmin
                ? () => Get.to(() => const GroupAnnouncementPage())
                : (logic.groupInfo.value.notification?.trim().isNotEmpty ??
                        false)
                    ? () => showGroupAnnouncementSheet(
                        Get.context!, logic.groupInfo.value.notification!)
                    : null),
        _settingRow('groupMyNickname'.tr,
            value: logic.myGroupNickname ?? 'groupNicknameUnset'.tr,
            onTap: logic.editMyGroupNickname),
      ]);
}
