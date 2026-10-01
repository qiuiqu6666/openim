import 'package:common_utils/common_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import 'user_profile _panel_logic.dart';
import '../contacts_logic.dart';
import '../star_burst_button.dart';

class UserProfilePanelPage extends StatelessWidget {
  final logic = Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile);

  UserProfilePanelPage({super.key});

  static const _background = Color(0xFFF5F6F8);
  static const _muted = Color(0xFF89909C);

  @override
  Widget build(BuildContext context) => Obx(() {
        final user = logic.userInfo.value;
        final canChat = !logic.isMyself &&
            (logic.isFriendship || logic.allowSendMsgNotFriend);
        final canAdd = !logic.isMyself &&
            !logic.isFriendship &&
            logic.isAllowAddFriend &&
            (!logic.isGroupMemberPage ||
                logic.forceCanAdd == true ||
                !logic.notAllowAddGroupMemberFriend.value);
        return Scaffold(
          backgroundColor: _background,
          appBar: AppBar(
            backgroundColor: _background,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
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
                  onPressed: logic.friendSetup,
                  icon: const Icon(Icons.more_horiz, size: 28),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _header(),
                if (canChat)
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
                if (canAdd)
                  _card([_row(StrRes.addFriend, onTap: logic.addFriend)]),
                if (logic.isFriendship)
                  _card([
                    _row('profileRemarkName'.tr,
                        value: user.remark, onTap: logic.editRemark),
                  ]),
                if (logic.isFriendship ||
                    logic.isMyself ||
                    logic.isGroupMemberPage &&
                        !logic.notAllowLookGroupMemberProfiles.value)
                  _card([
                    _row(StrRes.personalInfo, onTap: logic.viewPersonalInfo),
                  ]),
                if (logic.isGroupMemberPage &&
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

  Widget _header() {
    final user = logic.userInfo.value;
    final showID =
        !logic.isGroupMemberPage || !logic.notAllowAddGroupMemberFriend.value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 16, 22),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AvatarView(
            url: user.faceURL,
            text: user.nickname,
            width: 78,
            height: 78,
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
            if (showID) ...[
              const SizedBox(height: 6),
              Material(
                color: const Color(0xFFEBEDF1),
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: logic.copyID,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                          child: Text('ID: ${user.userID ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 14, color: _muted))),
                      const SizedBox(width: 8),
                      const Icon(Icons.copy_outlined, size: 15, color: _muted),
                    ]),
                  ),
                ),
              ),
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(
                    height: 0.5,
                    thickness: 0.5,
                    indent: 16,
                    color: Color(0xFFE9ECF1)),
              children[i],
            ],
          ]),
        ),
      );

  Widget _row(String title, {String? value, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
            if (value != null && value.isNotEmpty)
              Expanded(
                  child: Text(value,
                      textAlign: TextAlign.right,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, color: _muted))),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right,
                  size: 20, color: Color(0xFFB6BBC4)),
            ],
          ]),
        ),
      );
}
