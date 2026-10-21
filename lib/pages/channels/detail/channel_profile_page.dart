import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';
import '../presentation/channel_tokens.dart';
import '../presentation/channel_settings_row.dart';
import '../settings/channel_settings_page.dart';
import '../presentation/channel_avatar.dart';
import '../members/channel_members_page.dart';
import 'widgets/channel_more_menu.dart';

class ChannelProfilePage extends StatelessWidget {
  const ChannelProfilePage({super.key, required this.channel});
  final ChannelPreview channel;

  Future<void> _edit(BuildContext context) async {
    await channelRoute<void>(context, ChannelSettingsPage(channel: channel));
    if (context.mounted && channel.deleted) Navigator.pop(context);
  }

  Future<void> _more(BuildContext context, String action) async {
    final leave = action == 'leave';
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(channelText(
                    context,
                    leave ? (channel.owner ? '解散频道？' : '退出频道？') : '清空聊天记录？',
                    leave ? 'Leave channel?' : 'Clear chat history?')),
                content: Text(channelText(context, '仅影响本次本地预览。',
                    'This only affects the current local preview.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(channelText(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(channelText(context, leave ? '退出' : '清空',
                          leave ? 'Leave' : 'Clear')))
                ]));
    if (yes != true || !context.mounted) return;
    channel.update(() {
      if (leave) {
        if (channel.owner) {
          channel.deleted = true;
        } else {
          channel.subscribed = false;
        }
      } else {
        channel.posts.clear();
      }
    });
    if (leave) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: channel,
      builder: (context, _) => ChannelScaffold(
          title: channelText(context, '频道资料', 'Channel profile'),
          body: ListView(
              padding: const EdgeInsets.fromLTRB(0, 18, 0, 28),
              children: [
                Center(child: ChannelAvatar(bytes: channel.avatar, size: 88)),
                const SizedBox(height: 10),
                Text(channel.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 23, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                    channelText(context, '${channel.members.length}位订阅者',
                        '${channel.members.length} subscribers'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppTokens.textSecondary(
                            dark: Theme.of(context).brightness ==
                                Brightness.dark))),
                const SizedBox(height: 22),
                Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      _action(
                          context,
                          channel.notifications
                              ? Icons.notifications_active_outlined
                              : Icons.notifications_off_outlined,
                          channelText(
                              context,
                              channel.notifications ? '接收通知' : '静音',
                              channel.notifications
                                  ? 'Notifications'
                                  : 'Muted'),
                          () => channel.update(() =>
                              channel.notifications = !channel.notifications)),
                      const SizedBox(width: 8),
                      _action(
                          context,
                          Icons.search,
                          channelText(context, '搜索', 'Search'),
                          () => Navigator.pop(context, true)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Material(
                              color: ChannelTokens.surface(context),
                              borderRadius: BorderRadius.circular(12),
                              child: ChannelMoreMenu(
                                  owner: channel.owner,
                                  onSelected: (value) => _more(context, value),
                                  child: _actionContent(
                                      context,
                                      Icons.more_horiz,
                                      channelText(context, '更多', 'More'))))),
                    ])),
                const SizedBox(height: 14),
                ChannelSection(children: [
                  ChannelSettingsRow(
                      title: channelText(context, '频道别名', 'Channel alias'),
                      value: channelText(context, '待生成', 'Pending'),
                      onTap: () => channelUnavailable(context))
                ]),
                if (channel.owner) ...[
                  const SizedBox(height: 2),
                  ChannelSection(separated: true, children: [
                    ChannelSettingsRow(
                        title: channelText(context, '管理员', 'Administrators'),
                        onTap: () => channelRoute<void>(
                            context,
                            ChannelMembersPage(
                                channel: channel,
                                mode: ChannelMemberMode.admins))),
                    ChannelSettingsRow(
                        title: channelText(context, '订阅者', 'Subscribers'),
                        value: '${channel.members.length}',
                        onTap: () => channelRoute<void>(
                            context,
                            ChannelMembersPage(
                                channel: channel,
                                mode: ChannelMemberMode.subscribers))),
                    ChannelSettingsRow(
                        title: channelText(context, '添加订阅者', 'Add subscribers'),
                        onTap: () => channelRoute<void>(
                            context,
                            ChannelMembersPage(
                                channel: channel,
                                mode: ChannelMemberMode.subscribers,
                                adding: true))),
                    ChannelSettingsRow(
                        title: channelText(context, '频道设置', 'Channel settings'),
                        onTap: () => _edit(context)),
                  ]),
                ],
              ])));
  Widget _action(BuildContext context, IconData icon, String title,
          VoidCallback onTap) =>
      Expanded(
          child: Material(
              color: ChannelTokens.surface(context),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(12),
                  child: _actionContent(context, icon, title))));
  Widget _actionContent(BuildContext context, IconData icon, String title) =>
      ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: ChannelTokens.action(context)),
                    const SizedBox(height: 5),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: ChannelTokens.action(context),
                            fontSize: 14)),
                  ])));
}
