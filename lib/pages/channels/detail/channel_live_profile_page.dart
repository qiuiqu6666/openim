import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../../chat/group_setup/group_setup_logic.dart';
import '../../chat/group_setup/group_manage/group_member_permissions_page.dart';
import '../../chat/group_setup/loading/group_setup_loading.dart';
import '../presentation/channel_ui.dart';
import '../presentation/channel_tokens.dart';
import '../presentation/channel_settings_row.dart';
import 'widgets/channel_more_menu.dart';

/// 99chat group_profile.dart::_buildMobileChannelProfile, with OpenIM actions.
class ChannelLiveProfilePage extends StatelessWidget {
  const ChannelLiveProfilePage({super.key, required this.logic});
  final GroupSetupLogic logic;

  @override
  Widget build(BuildContext context) => Obx(() {
        final info = logic.groupInfo.value;
        final joined = logic.isJoinedGroup.value;
        final manager = joined &&
            logic.membership.resolved.value &&
            !logic.membership.failed.value &&
            logic.isOwnerOrAdmin;
        return ChannelScaffold(
          title: channelText(context, '频道', 'Channel'),
          body: ListView(
              padding: const EdgeInsets.fromLTRB(0, 18, 0, 28),
              children: [
                Center(
                    child: AvatarView(
                        width: 88,
                        height: 88,
                        url: info.faceURL,
                        file: logic.avatar.value,
                        text: info.groupName,
                        isGroup: true,
                        isCircle: true,
                        enabledPreview: true)),
                const SizedBox(height: 10),
                Text(info.groupName ?? '',
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                    info.memberCount == null
                        ? StrRes.synchronizing
                        : 'channelSubscriberCountLabel'
                            .trArgs(['${info.memberCount}']),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: ChannelTokens.muted(context))),
                if (!joined && !logic.membership.resolved.value)
                  GroupSetupLoading(
                      failed: logic.membership.failed.value,
                      onRetry: logic.refreshMembership),
                if (joined) ...[
                  const SizedBox(height: 22),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(children: [
                        _action(
                            context,
                            logic.isNotDisturb
                                ? Icons.notifications_off_outlined
                                : Icons.notifications_active_outlined,
                            channelText(
                                context,
                                logic.isNotDisturb ? '静音' : '接收通知',
                                logic.isNotDisturb ? 'Muted' : 'Notifications'),
                            logic.updating.value
                                ? null
                                : () => logic.setMuted(!logic.isNotDisturb)),
                        const SizedBox(width: 8),
                        _action(
                            context,
                            Icons.search,
                            channelText(context, '搜索', 'Search'),
                            logic.searchHistory),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Material(
                                color: ChannelTokens.surface(context),
                                borderRadius: BorderRadius.circular(12),
                                child: ChannelMoreMenu(
                                    owner: logic.isOwner,
                                    onSelected: (value) => value == 'clear'
                                        ? logic.clearChannelHistory()
                                        : logic.quitGroup(),
                                    child: _content(context, Icons.more_horiz,
                                        channelText(context, '更多', 'More'))))),
                      ])),
                  const SizedBox(height: 14),
                  ChannelSection(children: [
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(children: [
                          Text(channelText(context, '频道别名', 'Channel alias'),
                              style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Text('@${info.groupID}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                      color: ChannelTokens.action(context),
                                      fontSize: 16))),
                          IconButton(
                              tooltip: channelText(
                                  context, '频道二维码', 'Channel QR code'),
                              onPressed: logic.viewGroupQrcode,
                              icon: const Icon(Icons.qr_code_2)),
                        ])),
                  ]),
                  if (manager) ...[
                    const SizedBox(height: 2),
                    ChannelSection(separated: true, children: [
                      ChannelSettingsRow(
                          title: channelText(context, '管理员', 'Administrators'),
                          onTap: () => Get.to(() => GroupMemberPermissionsPage(
                              isChannel: true,
                              groupID: info.groupID,
                              owner: logic.isOwner,
                              mode: MemberPermissionMode.admins))),
                      ChannelSettingsRow(
                          title: channelText(context, '订阅者', 'Subscribers'),
                          value: info.memberCount?.toString(),
                          onTap: logic.viewGroupMembers),
                      ChannelSettingsRow(
                          title:
                              channelText(context, '添加订阅者', 'Add subscribers'),
                          onTap: logic.addMember),
                      ChannelSettingsRow(
                          title: channelText(
                              context, '移除订阅者', 'Remove subscribers'),
                          onTap: logic.removeMember),
                      ChannelSettingsRow(
                          title:
                              channelText(context, '频道设置', 'Channel settings'),
                          onTap: logic.groupManage),
                    ]),
                  ],
                ],
              ]),
        );
      });

  Widget _action(BuildContext context, IconData icon, String label,
          VoidCallback? action) =>
      Expanded(
          child: Material(
              color: ChannelTokens.surface(context),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                  onTap: action,
                  borderRadius: BorderRadius.circular(12),
                  child: _content(context, icon, label))));

  Widget _content(BuildContext context, IconData icon, String label) =>
      ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
              child: Column(children: [
                Icon(icon, size: 26, color: ChannelTokens.action(context)),
                const SizedBox(height: 5),
                Text(label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: ChannelTokens.action(context)))
              ])));
}
