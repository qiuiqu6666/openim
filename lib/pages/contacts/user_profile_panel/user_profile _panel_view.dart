import 'package:common_utils/common_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'user_profile _panel_logic.dart';
import 'friend_setup/friend_setup_logic.dart';
import '../contacts_logic.dart';
import '../star_burst_button.dart';
import '../../../theme/profile_tokens.dart';
import '../../mine/settings/openim_profile_service.dart';

class UserProfilePanelPage extends StatelessWidget {
  final logic = Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile);

  UserProfilePanelPage({super.key});

  static Color get _background => Styles.c_F8F9FA;
  static Color get _muted => Styles.c_8E9AB0;

  @override
  Widget build(BuildContext context) => Obx(() {
        final user = logic.userInfo.value;
        final canChat = !logic.isMyself &&
            (logic.isFriendship || logic.allowSendMsgNotFriend);
        final groupManager = logic.isGroupMemberPage &&
            (logic.iAmOwner.value || logic.iHaveAdminOrOwnerPermission.value);
        final canAdd = !logic.isMyself &&
            !logic.isFriendship &&
            (groupManager ||
                (logic.isAllowAddFriend &&
                    (!logic.isGroupMemberPage ||
                        logic.forceCanAdd == true ||
                        !logic.notAllowAddGroupMemberFriend.value)));
        return Scaffold(
          backgroundColor: _background,
          appBar: GlassAppBar(
            backgroundColor: _background,
            centerTitle: true,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Get.back(),
              icon: Icon(Icons.arrow_back_ios_new,
                  color: Styles.c_0089FF, size: 22),
            ),
            title: Text('profileDetails'.tr,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            actions: [
              if (logic.isFriendship)
                IconButton(
                  tooltip: 'profileMore'.tr,
                  icon: const Icon(Icons.more_horiz, size: 28),
                  onPressed: () => _showMore(context),
                ),
            ],
          ),
          bottomNavigationBar: !logic.isMyself && !logic.isFriendship
              ? _strangerActions(context, canAdd)
              : null,
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (!logic.isMyself && !logic.isFriendship) ...[
                  _card([
                    Padding(
                      padding: ProfileTokens.headerPadding,
                      child: _header(stranger: true),
                    )
                  ]),
                  _card([
                    _row(StrRes.gender,
                        value: user.gender == 1
                            ? StrRes.man
                            : user.gender == 2
                                ? StrRes.woman
                                : 'profileGenderPrivate'.tr),
                    if (logic.isFriendship || logic.isMyself || !logic.isGroupMemberPage ||
                        !logic.notAllowAddGroupMemberFriend.value)
                      _row(logic.showMemberIMID ? 'IM ID' : 'profileChatID'.tr,
                          value: logic.displayedUserID.isEmpty ? '—' : logic.displayedUserID,
                          valueColor: Styles.c_0089FF,
                          onTap: logic.copyID),
                    if (logic.isGroupMemberPage &&
                        logic.joinGroupTime.value > 0)
                      _row(StrRes.joinGroupDate,
                          value: DateUtil.formatDateMs(
                              logic.joinGroupTime.value < 1000000000000
                                  ? logic.joinGroupTime.value * 1000
                                  : logic.joinGroupTime.value,
                              format: 'yyyy-MM-dd HH:mm')),
                    if (logic.isGroupMemberPage &&
                        logic.inviterID.value.isNotEmpty)
                      _row('profileInviter'.tr,
                          value: logic.inviterName.value,
                          valueColor: Styles.c_0089FF,
                          onTap: logic.viewInviter),
                  ]),
                ] else
                  _header(),
                if (canChat && logic.isFriendship)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                    child: Row(children: [
                      _action('profileVoiceCall'.tr, Icons.call_outlined,
                          () => logic.callDirectly(video: false)),
                      const SizedBox(width: 8),
                      _action('profileVideoCall'.tr, Icons.videocam_outlined,
                          () => logic.callDirectly(video: true)),
                      const SizedBox(width: 8),
                      _action(StrRes.sendMessage, Icons.chat_bubble_outline,
                          logic.toChat,
                          primary: true),
                    ]),
                  ),
                if (logic.isFriendship)
                  _card([
                    _row('profileRemarkName'.tr,
                        value: user.remark, onTap: logic.editRemark),
                  ]),
                if (logic.isMyself)
                  _card([
                    _row(StrRes.personalInfo, onTap: logic.viewPersonalInfo),
                  ]),
                if (!logic.isMyself)
                  _card([
                    _row('profileCommonGroups'.tr,
                        value: logic.loadingCommonGroups.value
                            ? 'profileCommonGroupsLoading'.tr
                            : logic.commonGroupsFailed.value
                                ? 'profileCommonGroupsCountFailed'.tr
                                : '${logic.commonGroupCount.value ?? 0}',
                        onTap: logic.openCommonGroups),
                  ]),
                if (logic.isFriendship && !logic.isMyself)
                  _card([
                    _row('currentChatBackground'.tr,
                        onTap: logic.setChatBackground),
                  ]),
                if (logic.isGroupMemberPage &&
                    logic.isFriendship &&
                    (logic.joinGroupTime.value > 0 ||
                        logic.joinGroupMethod.value.isNotEmpty))
                  _card([
                    if (logic.joinGroupTime.value > 0)
                      _row(StrRes.joinGroupDate,
                          value: DateUtil.formatDateMs(
                              logic.joinGroupTime.value,
                              format: DateFormats.zh_y_mo_d)),
                    if (logic.joinGroupMethod.value.isNotEmpty)
                      _row(StrRes.joinGroupMethod,
                          value: logic.joinGroupMethod.value),
                  ]),
                if (logic.isFriendship)
                  _card([
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      child: Row(children: [
                        Expanded(
                            child: Text('profileAddBlacklist'.tr,
                                style: const TextStyle(fontSize: 16))),
                        CupertinoSwitch(
                          value: user.isBlacklist,
                          activeTrackColor: Styles.c_0089FF,
                          onChanged: logic.updatingBlacklist.value
                              ? null
                              : logic.setBlacklist,
                        ),
                      ]),
                    ),
                  ]),
              ],
            ),
          ),
        );
      });

  Future<void> _showMore(BuildContext context) async {
    final zh = (Get.locale ?? Get.deviceLocale)?.languageCode == 'zh';
    final action = await Get.bottomSheet<String>(
      BottomSheetView(
        items: [
          SheetItem(
            label: zh ? '分享联系人' : 'Share Contact',
            result: 'share',
          ),
          SheetItem(
            label: zh ? '删除好友' : 'Delete Friend',
            textStyle: Styles.ts_0C1C33_17sp.copyWith(
                color: Theme.of(context).colorScheme.error),
            result: 'delete',
          ),
          SheetItem(
            label: (logic.userInfo.value.isBlacklist
                ? 'profileRemoveBlacklist' : 'profileAddBlacklist').tr,
            result: 'blacklist',
          ),
        ],
      ),
      backgroundColor: Colors.transparent,
      useRootNavigator: true,
    );
    if (action == null || logic.isClosed) return;
    if (action == 'blacklist') {
      await logic.setBlacklist(!logic.userInfo.value.isBlacklist);
      return;
    }
    final actions = FriendSetupLogic()..userID = logic.userInfo.value.userID!;
    if (action == 'share') {
      actions.recommendToFriend();
    } else if (action == 'delete') {
      actions.deleteFromFriendList();
    }
  }

  Widget _strangerActions(BuildContext context, bool canAdd) => SafeArea(
        top: false,
        child: Padding(
          padding: ProfileTokens.actionsPadding,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (canAdd) ...[
              Button(
                text: 'profileAdd'.tr,
                enabled: !logic.userInfo.value.isBlacklist &&
                    !logic.updatingBlacklist.value,
                height: ProfileTokens.buttonHeight,
                radius: ProfileTokens.radius,
                textStyle: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
                onTap: logic.addFriend,
              ),
              const SizedBox(height: ProfileTokens.gap),
            ],
            Button(
              text: (logic.userInfo.value.isBlacklist
                      ? 'profileRemoveBlacklist'
                      : 'profileAddBlacklist')
                  .tr,
              enabled: !logic.updatingBlacklist.value,
              height: ProfileTokens.buttonHeight,
              radius: ProfileTokens.radius,
              enabledColor: _background,
              disabledColor: _background,
              border: Border.all(color: Styles.c_0089FF),
              textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color:
                      logic.updatingBlacklist.value ? _muted : Styles.c_0089FF),
              onTap: () =>
                  logic.setBlacklist(!logic.userInfo.value.isBlacklist),
            ),
          ]),
        ),
      );

  Widget _header({bool stranger = false}) {
    final user = logic.userInfo.value;
    final signature = OpenIMProfileService.signatureFromEx(user.ex).trim();
    final showID =
        logic.isFriendship || logic.isMyself || !logic.isGroupMemberPage || !logic.notAllowAddGroupMemberFriend.value;
    return Padding(
      padding: stranger
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(20, 22, 16, 22),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AvatarView(
            url: user.faceURL,
            text: user.nickname,
            width: stranger ? ProfileTokens.avatar : 78,
            height: stranger ? ProfileTokens.avatar : 78,
            isCircle: true,
            enabledPreview: true),
        const SizedBox(width: 14),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                  child: Text(
                      (user.nickname ?? '').trim().isNotEmpty
                          ? user.nickname!
                          : user.userID ?? '',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600))),
              if (user.gender == 1 || user.gender == 2) ...[
                const SizedBox(width: 6),
                Icon(user.gender == 1 ? Icons.male : Icons.female,
                    size: 20,
                    color:
                        user.gender == 1 ? Styles.c_0089FF : Colors.pinkAccent),
              ],
            ]),
            if (showID && logic.displayedUserID.isNotEmpty) ...[
              const SizedBox(height: 6),
              if (stranger)
                InkWell(
                  onTap: logic.copyID,
                  child: Text(logic.displayedUserID,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Styles.ts_8E9AB0_14sp
                          .copyWith(color: Styles.c_0089FF)),
                )
              else
                Material(
                  color: Styles.c_F0F2F6,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: logic.copyID,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Flexible(
                            child: Text(logic.displayedUserID,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14, color: _muted))),
                        const SizedBox(width: 8),
                        Icon(Icons.copy_outlined, size: 15, color: _muted),
                      ]),
                    ),
                  ),
                ),
            ],
            ...[
              const SizedBox(height: AppTokens.s3),
              Text(signature.isNotEmpty ? signature :
                  (Get.locale?.languageCode == 'zh' ? '暂未设置个性签名' : 'No bio set yet'),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Styles.ts_8E9AB0_14sp.copyWith(color: _muted)),
            ],
          ],
        )),
        if (logic.isFriendship &&
            !logic.isMyself &&
            Get.isRegistered<ContactsLogic>())
          Builder(
              builder: (context) => Obx(() {
                    final stars = Get.find<ContactsLogic>().stars;
                    final id = user.userID!;
                    final selected = stars.isStarred(id);
                    return StarBurstButton(
                      tooltip: (selected ? 'unstarFriend' : 'starFriend').tr,
                      starred: selected,
                      onPressed: stars.pending.contains(id)
                          ? null
                          : () => stars.toggle(id),
                      color: selected
                          ? Styles.c_FFB300
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    );
                  })),
      ]),
    );
  }

  Widget _action(String label, IconData icon, VoidCallback onTap,
          {bool primary = false}) =>
      Expanded(
        child: Material(
          color: primary ? Styles.c_0089FF : Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 16),
              child: Column(children: [
                Icon(icon,
                    size: 25,
                    color: primary ? Colors.white : const Color(0xFF202329)),
                const SizedBox(height: 10),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        height: 1.3,
                        color:
                            primary ? Colors.white : const Color(0xFF202329))),
              ]),
            ),
          ),
        ),
      );

  Widget _card(List<Widget> children) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Material(
          color: Styles.c_FFFFFF,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: 16,
                    color: Styles.c_E8EAEF),
              children[i],
            ],
          ]),
        ),
      );

  Widget _row(String title,
          {String? value, VoidCallback? onTap, Color? valueColor}) =>
      InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
            if (value != null && value.isNotEmpty)
              Expanded(
                  child: Text(value,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15, color: valueColor ?? _muted))),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFFB6BBC4)),
            ],
          ]),
        ),
      );
}
