import 'package:azlistview/azlistview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:openim_common/openim_common.dart';

import 'contacts_logic.dart';
import 'presence_label.dart';

class ContactsPage extends StatelessWidget {
  ContactsPage({super.key, ContactsLogic? logic})
      : logic = logic ??
            (Get.isRegistered<ContactsLogic>()
                ? Get.find<ContactsLogic>()
                : Get.put(ContactsLogic()));

  final ContactsLogic logic;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Styles.c_F8F9FA,
        appBar: GlassAppBar(
          toolbarHeight: 56.h,
          titleSpacing: 16.w,
          title: Text(StrRes.contacts,
              style: TextStyle(
                  color: Styles.c_0C1C33,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w600)),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: IconButton(
                onPressed: logic.addContacts,
                tooltip: StrRes.addFriend,
                icon: Image.asset('assets/images/contact_plus_99chat.png',
                    package: 'openim_common',
                    width: 24.w,
                    height: 24.w,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.add, size: 24.w, color: Styles.c_0089FF)),
              ),
            ),
          ],
        ),
        body: Column(children: [
          Material(
            color: Styles.c_FFFFFF,
            child: InkWell(
              onTap: logic.searchContacts,
              child: Padding(
                padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 8.h),
                child: Container(
                  height: 40.h,
                  padding: EdgeInsets.symmetric(horizontal: 12.w),
                  decoration: BoxDecoration(
                      color: Styles.c_F4F5F7,
                      borderRadius: BorderRadius.circular(10.r)),
                  child: Row(children: [
                    Icon(Icons.search, size: 19.w, color: Styles.c_8E9AB0),
                    8.horizontalSpace,
                    Text(StrRes.search, style: Styles.ts_8E9AB0_15sp),
                  ]),
                ),
              ),
            ),
          ),
          Expanded(child: Obx(() => _buildDirectory(context))),
        ]),
      );

  Widget _buildDirectory(BuildContext context) {
    final chinese =
        (Get.locale ?? Localizations.localeOf(context)).languageCode == 'zh';
    final starred = <ISUserInfo>[];
    final regular = <ISUserInfo>[];
    for (final friend in logic.friends) {
      (logic.stars.isStarred(friend.userID!) ? starred : regular).add(friend);
    }
    final rows = <_DirectoryRow>[
      _DirectoryRow.action(
          chinese ? '新的朋友' : StrRes.newFriend,
          'assets/images/contact_new_99chat.png',
          logic.newFriend,
          logic.friendApplicationCount),
      _DirectoryRow.action(
          StrRes.newGroupRequest,
          'assets/images/contact_notice_99chat.png',
          logic.newGroup,
          logic.groupApplicationCount),
      _DirectoryRow.action(chinese ? '我的群聊' : StrRes.myGroup,
          'assets/images/contact_groups_99chat.png', logic.myGroup, 0),
      for (final friend in starred) _DirectoryRow.friend(friend, starred: true),
      for (final friend in regular) _DirectoryRow.friend(friend),
      _DirectoryRow.footer(),
    ];
    SuspensionUtil.setShowSuspensionStatus(rows);
    final tags = <String>['↑'];
    for (final row in rows.where((row) => row.friend != null)) {
      final tag = row.getSuspensionTag();
      if (!tags.contains(tag)) tags.add(tag);
    }
    return AzListView(
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      data: rows,
      itemCount: rows.length,
      physics: const BouncingScrollPhysics(),
      itemBuilder: (_, index) {
        final row = rows[index];
        if (row.isFooter) return _buildFooter(context);
        if (row.friend != null) {
          final id = row.friend!.userID!;
          return VisibilityDetector(
            key: ValueKey('contact-presence-$id'),
            onVisibilityChanged: (info) =>
                logic.setPresenceVisible(id, info.visibleFraction > 0),
            child: _buildFriend(row.friend!),
          );
        }
        return _buildAction(row);
      },
      susItemBuilder: (_, index) {
        final tag = rows[index].getSuspensionTag();
        if (tag == '↑' || tag == '~') return const SizedBox.shrink();
        return Container(
          height: 32.h,
          padding: EdgeInsets.only(left: 16.w),
          alignment: Alignment.centerLeft,
          color: Styles.c_F8F9FA,
          child: Text(tag == '★' ? 'starredFriend'.tr : tag,
              style: Styles.ts_8E9AB0_12sp),
        );
      },
      susItemHeight: 32.h,
      indexBarData: logic.friends.isEmpty ? const [] : tags,
      indexBarWidth: 24.w,
      indexBarItemHeight: 16.h,
      indexBarMargin: EdgeInsets.only(
          right: 2.w, bottom: MediaQuery.paddingOf(context).bottom),
      indexBarOptions: IndexBarOptions(
        needRebuild: true,
        textStyle: Styles.ts_8E9AB0_12sp,
        selectTextStyle: Styles.ts_FFFFFF_12sp,
        downItemDecoration:
            BoxDecoration(color: Styles.c_0089FF, shape: BoxShape.circle),
        indexHintDecoration: BoxDecoration(
            color: Styles.c_0089FF, borderRadius: BorderRadius.circular(12.r)),
      ),
    );
  }

  Widget _buildAction(_DirectoryRow row) => _buildRow(
        onTap: row.onTap,
        avatar: Stack(clipBehavior: Clip.none, children: [
          ClipOval(
            child: Transform.scale(
              scale: row.icon!.contains('contact_notice_') ? 1.5 : 1,
              child: Image.asset(row.icon!,
                  package: 'openim_common',
                  width: 44.w,
                  height: 44.w,
                  fit: BoxFit.cover),
            ),
          ),
          if (row.count > 0)
            Positioned(
              top: -3.h,
              right: -4.w,
              child: Container(
                constraints: BoxConstraints(minWidth: 17.w),
                height: 17.h,
                padding: EdgeInsets.symmetric(horizontal: 3.w),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Styles.c_FF381F,
                    borderRadius: BorderRadius.circular(9.r),
                    border: Border.all(color: Styles.c_FFFFFF)),
                child: Text(row.count > 99 ? '99+' : '${row.count}',
                    style: const TextStyle(color: Colors.white, fontSize: 9)),
              ),
            ),
        ]),
        title: row.label!,
      );

  Widget _buildFriend(ISUserInfo friend) => Obx(() => _buildRow(
        onTap: () => logic.viewFriend(friend),
        avatar: AvatarView(
            url: friend.faceURL,
            text: friend.showName,
            width: 44.w,
            height: 44.w),
        title: friend.showName,
        reserveSubtitle: true,
        subtitle: logic.presence.users[friend.userID] == null
            ? null
            : PresenceLabel(presence: logic.presence.users[friend.userID]!),
        trailing: logic.stars.isStarred(friend.userID!)
            ? Builder(
                builder: (context) => Tooltip(
                    message: 'starredFriend'.tr,
                    child: Icon(Icons.star_rounded,
                        size: 20.w, color: Styles.c_FFB300)))
            : null,
      ));

  Widget _buildRow(
          {required Widget avatar,
          required String title,
          Widget? trailing,
          Widget? subtitle,
          bool reserveSubtitle = false,
          VoidCallback? onTap}) =>
      Material(
        color: Styles.c_FFFFFF,
        child: InkWell(
          onTap: onTap,
          child: Column(children: [
            SizedBox(
              height: 63.h,
              child: Padding(
                padding: EdgeInsets.only(left: 16.w, right: 32.w),
                child: Row(children: [
                  SizedBox(width: 44.w, height: 44.w, child: avatar),
                  12.horizontalSpace,
                  Expanded(
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Styles.c_0C1C33,
                              fontSize: 16.sp,
                              fontWeight: FontWeight.w500)),
                      if (subtitle != null)
                        subtitle
                      else if (reserveSubtitle)
                        SizedBox(height: 16.h),
                    ],
                  )),
                  if (trailing != null) trailing,
                ]),
              ),
            ),
            Padding(
                padding: EdgeInsets.only(left: 72.w),
                child: Container(height: 0.6, color: Styles.c_E8EAEF)),
          ]),
        ),
      );

  Widget _buildFooter(BuildContext context) {
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final label = logic.friends.isEmpty
        ? (chinese ? '无联系人' : 'No contacts')
        : (chinese
            ? '${logic.friends.length}位联系人'
            : '${logic.friends.length} contacts');
    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 16.h, 32.w, 24.h),
      child: Center(
          child: logic.friendsLoading.value
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(label, style: Styles.ts_8E9AB0_13sp)),
    );
  }
}

class _DirectoryRow implements ISuspensionBean {
  _DirectoryRow.action(this.label, this.icon, this.onTap, this.count)
      : friend = null,
        isFooter = false,
        tag = '↑';
  _DirectoryRow.friend(this.friend, {bool starred = false})
      : label = null,
        icon = null,
        onTap = null,
        count = 0,
        isFooter = false,
        tag = starred ? '★' : friend!.getSuspensionTag();
  _DirectoryRow.footer()
      : label = null,
        icon = null,
        onTap = null,
        count = 0,
        friend = null,
        isFooter = true,
        tag = '~';

  final String? label;
  final String? icon;
  final VoidCallback? onTap;
  final int count;
  final ISUserInfo? friend;
  final bool isFooter;
  final String tag;

  @override
  bool isShowSuspension = false;
  @override
  String getSuspensionTag() => tag;
}
