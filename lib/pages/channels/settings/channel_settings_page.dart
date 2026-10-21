import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';
import '../presentation/channel_avatar.dart';
import '../presentation/channel_settings_row.dart';
import '../presentation/channel_tokens.dart';
import '../members/channel_members_page.dart';
import 'channel_type_page.dart';

class ChannelSettingsPage extends StatefulWidget {
  const ChannelSettingsPage(
      {super.key, required this.channel, this.editing = false});
  final ChannelPreview channel;
  final bool editing;
  @override
  State<ChannelSettingsPage> createState() => _ChannelSettingsPageState();
}

class _ChannelSettingsPageState extends State<ChannelSettingsPage> {
  late final _name = TextEditingController(text: widget.channel.name);
  late final _description =
      TextEditingController(text: widget.channel.description);
  late Uint8List? _avatar = widget.channel.avatar;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty || !widget.channel.owner) return;
    widget.channel.update(() {
      widget.channel.name = _name.text.trim();
      widget.channel.description = _description.text.trim();
      widget.channel.avatar = _avatar;
    });
    Navigator.pop(context);
  }

  Future<void> _delete({bool clearOnly = false}) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(channelText(
                    context,
                    clearOnly ? '清空聊天记录？' : '解散频道？',
                    clearOnly ? 'Clear chat history?' : 'Delete channel?')),
                content: Text(channelText(context, '将删除本次预览中的频道和消息。',
                    'This removes the channel and its posts from this preview.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(channelText(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(channelText(context, '删除', 'Delete')))
                ]));
    if (confirmed != true || !mounted) return;
    widget.channel.update(() {
      if (clearOnly) {
        widget.channel.posts.clear();
      } else {
        widget.channel.deleted = true;
      }
    });
    if (!clearOnly) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.channel,
      builder: (context, _) {
        if (!widget.channel.owner) {
          return ChannelScaffold(
              title: channelText(context, '频道设置', 'Channel settings'),
              body: ChannelEmpty(
                  title: channelText(context, '无权修改', 'Access restricted'),
                  message: channelText(context, '只有频道主可以修改设置',
                      'Only the owner can edit settings.')));
        }
        return ChannelScaffold(
            whiteBackground: false,
            title: channelText(context, widget.editing ? '频道资料' : '频道设置',
                widget.editing ? 'Channel profile' : 'Channel settings'),
            actions: [
              if (widget.editing)
                TextButton(
                    onPressed: _name.text.trim().isEmpty ? null : _save,
                    child: Text(channelText(context, '保存', 'Save')))
            ],
            body: ListView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                children: [
                  if (!widget.editing)
                    ChannelSection(children: [
                      InkWell(
                          onTap: () async {
                            await channelRoute<void>(
                                context,
                                ChannelSettingsPage(
                                    channel: widget.channel, editing: true));
                            if (mounted) setState(() {});
                          },
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(children: [
                                ChannelAvatar(
                                    bytes: widget.channel.avatar, size: 58),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          channelText(
                                              context, '频道名称', 'Channel name'),
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: ChannelTokens.muted(
                                                  context))),
                                      const SizedBox(height: 4),
                                      Text(widget.channel.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w600)),
                                    ])),
                                const Icon(Icons.chevron_right),
                              ]))),
                    ]),
                  if (widget.editing)
                    ChannelSection(children: [
                      Padding(
                          padding: const EdgeInsets.all(AppTokens.s4),
                          child: Row(children: [
                            ChannelAvatar(
                                bytes: _avatar,
                                onChanged: (value) =>
                                    setState(() => _avatar = value)),
                            const SizedBox(width: AppTokens.s3),
                            Expanded(
                                child: TextField(
                                    controller: _name,
                                    maxLength: 50,
                                    onChanged: (_) => setState(() {}),
                                    decoration: InputDecoration(
                                        labelText: channelText(
                                            context, '频道名称', 'Channel name'),
                                        counterText: '',
                                        border: const UnderlineInputBorder()))),
                          ])),
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.s5),
                          child: TextField(
                              controller: _description,
                              minLines: 1,
                              maxLines: 4,
                              maxLength: 200,
                              decoration: InputDecoration(
                                  labelText: channelText(
                                      context, '频道简介', 'Description'),
                                  border: InputBorder.none,
                                  counterText: '')))
                    ]),
                  if (!widget.editing) ...[
                    ChannelSection(separated: true, children: [
                      ChannelSettingsRow(
                          title: channelText(context, '频道类型', 'Channel type'),
                          onTap: () => channelRoute<void>(context,
                              ChannelTypePage(channel: widget.channel))),
                      ChannelSettingsRow(
                          title: channelText(context, '管理员', 'Administrators'),
                          onTap: () => channelRoute<void>(
                              context,
                              ChannelMembersPage(
                                  channel: widget.channel,
                                  mode: ChannelMemberMode.admins))),
                      ChannelSettingsRow(
                          title: channelText(context, '订阅者', 'Subscribers'),
                          onTap: () => channelRoute<void>(
                              context,
                              ChannelMembersPage(
                                  channel: widget.channel,
                                  mode: ChannelMemberMode.subscribers))),
                      ChannelSettingsRow(
                          title:
                              channelText(context, '添加订阅者', 'Add subscribers'),
                          onTap: () => channelRoute<void>(
                              context,
                              ChannelMembersPage(
                                  channel: widget.channel,
                                  mode: ChannelMemberMode.subscribers,
                                  adding: true))),
                    ]),
                    ChannelSection(children: [
                      IntrinsicHeight(
                          child: Row(children: [
                        _operation(
                            channelText(context, '清空消息', 'Clear messages'),
                            () => _delete(clearOnly: true)),
                        const VerticalDivider(
                            width: 1, thickness: .5, indent: 16, endIndent: 16),
                        _operation(
                            channelText(context, '转让创建人', 'Transfer owner'),
                            () => channelUnavailable(context)),
                        const VerticalDivider(
                            width: 1, thickness: .5, indent: 16, endIndent: 16),
                        _operation(
                            channelText(context, '解散频道', 'Delete channel'),
                            _delete),
                      ]))
                    ]),
                  ],
                ]));
      });
  Widget _operation(String title, VoidCallback onTap) => Expanded(
      child: InkWell(
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 18),
              child: Text(title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.error)))));
}
