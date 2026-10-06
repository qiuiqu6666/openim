import 'package:common_utils/common_utils.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart' show GroupInfo;
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';

import '../../../services/moments_repository.dart';
import '../../../theme/profile_tokens.dart';
import '../../mine/settings/openim_profile_service.dart';
import '../../mine/settings/widgets/settings_widgets.dart';
import '../../moments/moments_page.dart';
import '../../moments/privacy/widgets/moments_peer_privacy_controls.dart';
import '../contacts_logic.dart';
import '../star_burst_button.dart';
import 'friend_setup/friend_setup_logic.dart';
import 'user_profile _panel_logic.dart';
import 'user_profile_tokens.dart';
import 'widgets/user_profile_identity.dart';
import 'widgets/user_profile_load_state.dart';
import 'widgets/user_profile_quick_actions.dart';
import '../../group_features/sangong/profile/sangong_profile_surface.dart';
import '../../group_features/sangong/profile/sangong_profile_panel.dart';
import '../../group_features/data/group_feature_store.dart';

class UserProfilePanelPage extends StatelessWidget {
  UserProfilePanelPage(
      {super.key,
      this.momentsRepository,
      this.groupFeatureStore,
      this.loadGameGroups});

  final logic = Get.find<UserProfilePanelLogic>(tag: GetTags.userProfile);
  final MomentsRepository? momentsRepository;
  final GroupFeatureStore? groupFeatureStore;
  final Future<List<GroupInfo>> Function()? loadGameGroups;

  @override
  Widget build(BuildContext context) => Obx(() {
        final user = logic.userInfo.value;
        final ready = logic.profileLayoutReady.value;
        final canChat = !logic.isMyself &&
            (logic.isFriendship || logic.allowSendMsgNotFriend);
        final groupManager = logic.isGroupMemberPage &&
            (logic.iAmOwner.value || logic.iHaveAdminOrOwnerPermission.value);
        final canAdd = !logic.isMyself &&
            !logic.isFriendship &&
            logic.hasActiveGroupMemberContext &&
            (groupManager ||
                (logic.isAllowAddFriend &&
                    (!logic.isGroupMemberPage ||
                        logic.forceCanAdd == true ||
                        !logic.notAllowAddGroupMemberFriend.value)));
        final background = UserProfileTokens.background(context);
        final friend = logic.isFriendship && !logic.isMyself;
        return Scaffold(
          backgroundColor: background,
          extendBodyBehindAppBar: true,
          appBar: GlassAppBar(
            opaque: true,
            backgroundColor: background,
            foregroundColor: UserProfileTokens.text(context),
            centerTitle: true,
            leading: IconButton(
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: () => Get.back(),
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppTokens.accent,
                  size: UserProfileTokens.navigationIconSize),
            ),
            title: Text('profileDetails'.tr,
                style: TextStyle(
                    color: UserProfileTokens.text(context),
                    fontSize: UserProfileTokens.rowFontSize,
                    fontWeight: FontWeight.w600)),
            actions: [
              if (ready && friend)
                IconButton(
                  tooltip: 'profileMore'.tr,
                  icon: const Icon(Icons.more_horiz,
                      size: UserProfileTokens.menuIconSize),
                  onPressed: () => _showMore(context),
                ),
            ],
          ),
          bottomNavigationBar: ready && !logic.isMyself && !logic.isFriendship
              ? _strangerActions(context, canAdd)
              : null,
          body: SangongProfileSurface(
              store: groupFeatureStore,
              loadGroups: loadGameGroups,
              userID: user.userID ?? '',
              groupID: logic.groupID,
              child: SafeArea(
                top: false,
                child: !ready
                    ? UserProfileLoadState(
                        failed: logic.initialProfileFailed.value,
                        onRetry: logic.retryInitialProfile,
                      )
                    : ListView(
                        padding: EdgeInsets.only(
                            top: MediaQuery.paddingOf(context).top +
                                NavigationGlassTokens.toolbarHeight,
                            bottom: AppTokens.s7),
                        children: [
                          if (!logic.isMyself && !logic.isFriendship) ...[
                            _card(context, [
                              Padding(
                                padding: ProfileTokens.headerPadding,
                                child: _header(context, compact: true),
                              )
                            ]),
                            _card(context, [
                              _row(context, StrRes.gender,
                                  value: user.gender == 1
                                      ? StrRes.man
                                      : user.gender == 2
                                          ? StrRes.woman
                                          : 'profileGenderPrivate'.tr),
                              if (_showAccount)
                                _row(
                                    context,
                                    logic.showMemberIMID
                                        ? 'IM ID'
                                        : 'profileChatID'.tr,
                                    value: logic.displayedUserID.isEmpty
                                        ? '—'
                                        : logic.displayedUserID,
                                    valueColor: AppTokens.accent,
                                    onTap: logic.copyID),
                              if (logic.isGroupMemberPage &&
                                  logic.joinGroupTime.value > 0)
                                _row(context, StrRes.joinGroupDate,
                                    value: _joinDate(withTime: true)),
                              if (logic.isGroupMemberPage &&
                                  logic.inviterID.value.isNotEmpty)
                                _row(context, 'profileInviter'.tr,
                                    value: logic.inviterName.value,
                                    valueColor: AppTokens.accent,
                                    onTap: logic.viewInviter),
                            ]),
                          ] else
                            _header(context),
                          SangongInlineProfilePanel(userID: user.userID ?? ''),
                          if (canChat && friend)
                            UserProfileQuickActions(
                              voiceLabel: 'profileVoiceCall'.tr,
                              videoLabel: 'profileVideoCall'.tr,
                              messageLabel: StrRes.sendMessage,
                              onVoice: () => logic.callDirectly(video: false),
                              onVideo: () => logic.callDirectly(video: true),
                              onMessage: logic.toChat,
                            ),
                          if (friend || logic.isMyself)
                            _card(
                                context,
                                [
                                  if (friend)
                                    _row(context, 'profileRemarkName'.tr,
                                        key: 'user_profile_remark',
                                        value: user.remark,
                                        onTap: logic.editRemark),
                                  if (logic.isMyself)
                                    _row(context, StrRes.personalInfo,
                                        onTap: logic.viewPersonalInfo),
                                  _row(
                                      context, _text(context, '朋友圈', 'Moments'),
                                      key: 'user_profile_moments', onTap: () {
                                    if (ModalRoute.of(context)?.isCurrent ==
                                        false) {
                                      return;
                                    }
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => MomentsPage(
                                          repository: momentsRepository,
                                          authorId: user.userID,
                                          profileUser: MomentUser(
                                              userId: user.userID ?? '',
                                              nickname: user.nickname ?? '',
                                              avatarUrl: user.faceURL ?? '',
                                              remark: user.remark ?? ''),
                                        ),
                                      ),
                                    );
                                  }),
                                  if (friend && user.userID?.isNotEmpty == true)
                                    MomentsPeerPrivacyControls(
                                      userId: user.userID!,
                                      repository: momentsRepository,
                                      separator: _divider(context),
                                    ),
                                ],
                                key: 'user_profile_personal_group'),
                          if (logic.isGroupMemberPage &&
                              friend &&
                              (logic.joinGroupTime.value > 0 ||
                                  logic.joinGroupMethod.value.isNotEmpty))
                            _card(context, [
                              if (logic.joinGroupTime.value > 0)
                                _row(context, StrRes.joinGroupDate,
                                    value: _joinDate()),
                              if (logic.joinGroupMethod.value.isNotEmpty)
                                _row(context, StrRes.joinGroupMethod,
                                    value: logic.joinGroupMethod.value),
                            ]),
                          if (friend)
                            _card(
                                context,
                                [
                                  _row(context, 'profileCommonGroups'.tr,
                                      key: 'user_profile_common_groups',
                                      value: logic.loadingCommonGroups.value
                                          ? 'profileCommonGroupsLoading'.tr
                                          : logic.commonGroupsFailed.value
                                              ? 'profileCommonGroupsCountFailed'
                                                  .tr
                                              : '${logic.commonGroupCount.value ?? 0}',
                                      onTap: logic.openCommonGroups),
                                  if (friend)
                                    _row(context, 'currentChatBackground'.tr,
                                        key: 'user_profile_background',
                                        onTap: logic.setChatBackground),
                                ],
                                key: 'user_profile_conversation_group'),
                          if (friend)
                            _card(
                                context,
                                [
                                  SettingsCell(
                                    key: const ValueKey(
                                        'user_profile_blacklist'),
                                    title: 'profileAddBlacklist'.tr,
                                    showArrow: false,
                                    showDivider: false,
                                    trailing: CupertinoSwitch(
                                      value: user.isBlacklist,
                                      activeTrackColor: AppTokens.accent,
                                      onChanged: logic.updatingBlacklist.value
                                          ? null
                                          : logic.setBlacklist,
                                    ),
                                  ),
                                ],
                                key: 'user_profile_safety_group'),
                        ],
                      ),
              )),
        );
      });

  bool get _showAccount =>
      !logic.isGroupMemberPage || logic.displayedUserID.isNotEmpty;

  String _text(BuildContext context, String zh, String en) =>
      Localizations.localeOf(context).languageCode == 'zh' ? zh : en;

  String _joinDate({bool withTime = false}) {
    final value = logic.joinGroupTime.value;
    return DateUtil.formatDateMs(value < 1000000000000 ? value * 1000 : value,
        format: withTime ? 'yyyy-MM-dd HH:mm' : DateFormats.zh_y_mo_d);
  }

  Widget _header(BuildContext context, {bool compact = false}) {
    final user = logic.userInfo.value;
    final signature = OpenIMProfileService.signatureFromEx(user.ex).trim();
    final nickname = (user.nickname ?? '').trim();
    return UserProfileIdentity(
      key: const ValueKey('user_profile_identity'),
      compact: compact,
      name: nickname.isNotEmpty
          ? nickname
          : (_showAccount && logic.displayedUserID.isNotEmpty
              ? logic.displayedUserID
              : _text(context, '用户', 'User')),
      avatarUrl: user.faceURL,
      gender: user.gender,
      account: _showAccount ? logic.displayedUserID : '',
      // Group account disclosure arrives separately from the profile metadata.
      reserveAccountSpace: true,
      copyLabel: _text(context, '复制聊天号', 'Copy chat ID'),
      onCopy: logic.copyID,
      signature: signature.isNotEmpty
          ? signature
          : _text(
              context, logic.isMyself ? '暂未设置个性签名' : '对方什么都没有写', 'No bio yet'),
      trailing: logic.isFriendship &&
              !logic.isMyself &&
              Get.isRegistered<ContactsLogic>()
          ? Obx(() {
              final stars = Get.find<ContactsLogic>().stars;
              final id = user.userID!;
              final selected = stars.isStarred(id);
              return Material(
                color: UserProfileTokens.account(context),
                shape: const CircleBorder(),
                child: StarBurstButton(
                  tooltip: (selected ? 'unstarFriend' : 'starFriend').tr,
                  starred: selected,
                  onPressed: stars.pending.contains(id)
                      ? null
                      : () => stars.toggle(id),
                  color: selected
                      ? Styles.c_FFB300
                      : UserProfileTokens.muted(context),
                ),
              );
            })
          : null,
    );
  }

  Widget _divider(BuildContext context) => Divider(
      height: 1,
      thickness: .5,
      indent: AppTokens.s5,
      endIndent: AppTokens.s5,
      color: UserProfileTokens.divider(context));

  Widget _card(BuildContext context, List<Widget> children, {String? key}) =>
      SettingsGroup(
        key: key == null ? null : ValueKey(key),
        margin: UserProfileTokens.cardMargin,
        backgroundColor: UserProfileTokens.card(context),
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) _divider(context),
            children[i],
          ],
        ],
      );

  Widget _row(BuildContext context, String title,
          {String? key,
          String? value,
          VoidCallback? onTap,
          Color? valueColor}) =>
      SettingsCell(
        key: key == null ? null : ValueKey(key),
        title: title,
        value: value?.isNotEmpty == true ? value : null,
        showArrow: onTap != null,
        showDivider: false,
        onTap: onTap,
        valueStyle: TextStyle(
            fontSize: AppTokens.secondaryFontSize,
            color: valueColor ?? UserProfileTokens.muted(context)),
      );

  Future<void> _showMore(BuildContext context) async {
    final zh = (Get.locale ?? Get.deviceLocale)?.languageCode == 'zh';
    final action = await Get.bottomSheet<String>(
      BottomSheetView(items: [
        SheetItem(label: zh ? '分享联系人' : 'Share Contact', result: 'share'),
        SheetItem(
            label: zh ? '删除好友' : 'Delete Friend',
            textStyle: Styles.ts_0C1C33_17sp
                .copyWith(color: Theme.of(context).colorScheme.error),
            result: 'delete'),
        SheetItem(
            label: (logic.userInfo.value.isBlacklist
                    ? 'profileRemoveBlacklist'
                    : 'profileAddBlacklist')
                .tr,
            result: 'blacklist'),
      ]),
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
              if (!logic.canPrepareFriendAdd) ...[
                Text(
                  (Get.locale?.languageCode == 'en')
                      ? 'This person has not shared their chat ID. Ask them to share a QR code or contact card.'
                      : '对方未公开聊天号，请让对方分享二维码或名片。',
                  key: const ValueKey('user_profile_add_method_hint'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: UserProfileTokens.muted(context)),
                ),
                const SizedBox(height: ProfileTokens.gap),
              ],
              Button(
                  text: StrRes.addFriend,
                  enabledColor: AppTokens.accent,
                  enabled: !logic.userInfo.value.isBlacklist &&
                      !logic.updatingBlacklist.value &&
                      !logic.preparingFriendAdd.value,
                  height: ProfileTokens.buttonHeight,
                  radius: ProfileTokens.radius,
                  textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimary),
                  onTap: logic.addFriend),
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
                enabledColor: UserProfileTokens.background(context),
                disabledColor: UserProfileTokens.background(context),
                border: Border.all(color: AppTokens.accent),
                textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: logic.updatingBlacklist.value
                        ? UserProfileTokens.muted(context)
                        : AppTokens.accent),
                onTap: () =>
                    logic.setBlacklist(!logic.userInfo.value.isBlacklist)),
          ]),
        ),
      );
}
