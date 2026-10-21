import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../models/channel_preview.dart';
import '../presentation/channel_ui.dart';
import '../presentation/channel_tokens.dart';
import '../presentation/channel_settings_row.dart';

enum ChannelMemberMode { admins, subscribers, removed }

class ChannelMembersPage extends StatefulWidget {
  const ChannelMembersPage(
      {super.key,
      required this.channel,
      required this.mode,
      this.adding = false});
  final ChannelPreview channel;
  final ChannelMemberMode mode;
  final bool adding;
  @override
  State<ChannelMembersPage> createState() => _ChannelMembersPageState();
}

class _ChannelMembersPageState extends State<ChannelMembersPage> {
  @override
  void initState() {
    super.initState();
    if (widget.adding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _add();
      });
    }
  }

  final _selected = <String>{};
  String _query = "";
  bool get _admins => widget.mode == ChannelMemberMode.admins;
  bool get _removed => widget.mode == ChannelMemberMode.removed;

  Future<void> _add() async {
    final candidates = ['小林（示例）', '陈晨（示例）', '阿宁（示例）']
        .where((name) => _admins
            ? !widget.channel.administrators.contains(name)
            : !widget.channel.members.contains(name))
        .toList();
    final name = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        builder: (context) => ListView(shrinkWrap: true, children: [
              ChannelCaption(channelText(context, '选择示例用户 · 仅本地预览',
                  'Select an example user · Local preview')),
              if (candidates.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(AppTokens.s7),
                    child: Text(
                        channelText(context, '没有可添加的用户', 'No users to add'))),
              for (final name in candidates)
                ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(name),
                    onTap: () => Navigator.pop(context, name)),
            ]));
    if (!mounted || name == null) return;
    widget.channel.update(() {
      if (!widget.channel.members.contains(name)) {
        widget.channel.members.add(name);
      }
      widget.channel.removedMembers.remove(name);
      if (_admins) widget.channel.administrators.add(name);
    });
  }

  Future<void> _remove() async {
    if (_selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(
                    channelText(context, '移除所选用户？', 'Remove selected users?')),
                content: Text(channelText(context, '所选用户会移至被移除的用户列表。',
                    'Selected users will move to the removed users list.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(channelText(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(channelText(context, '移除', 'Remove')))
                ]));
    if (confirmed != true || !mounted) return;
    widget.channel.update(() {
      for (final name in _selected) {
        if (name == '我') continue;
        widget.channel.members.remove(name);
        widget.channel.administrators.remove(name);
        if (!widget.channel.removedMembers.contains(name)) {
          widget.channel.removedMembers.add(name);
        }
      }
    });
    setState(() {
      _selected.clear();
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.channel,
      builder: (context, _) {
        if (!widget.channel.owner) {
          return ChannelScaffold(
              title: channelText(context, '频道成员', 'Channel members'),
              body: ChannelEmpty(
                  title: channelText(context, '无权查看', 'Access restricted'),
                  message: channelText(context, '只有频道所有者和管理员才能看到这个菜单',
                      'Only owners and administrators can view this menu.')));
        }
        final allNames = _removed
            ? widget.channel.removedMembers
            : _admins
                ? widget.channel.administrators.toList()
                : widget.channel.members;
        final names = allNames
            .where((name) => name.toLowerCase().contains(_query.toLowerCase()))
            .toList();
        return ChannelScaffold(
            title: channelText(
                context,
                _removed
                    ? '被移除的用户'
                    : _admins
                        ? '管理员'
                        : '${allNames.length}位订阅者',
                _removed
                    ? 'Removed users'
                    : _admins
                        ? 'Administrators'
                        : '${allNames.length} subscribers'),
            whiteBackground: !_admins,
            body: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  if (_admins) ...[
                    ChannelSection(children: [
                      ChannelCaption(channelText(context, '创建人', 'Creator')),
                      for (final name in names.where((name) => name == '我'))
                        _row(name),
                    ]),
                    ChannelSection(children: [
                      ChannelCaption(channelText(
                          context,
                          '管理员 (${widget.channel.administrators.where((name) => name != '我').length}/19)',
                          'Administrators (${widget.channel.administrators.where((name) => name != '我').length}/19)')),
                      ListTile(
                          leading: Icon(Icons.add_circle_outline,
                              color: ChannelTokens.action(context)),
                          title: Text(
                              channelText(
                                  context, '添加管理员', 'Add administrator'),
                              style: TextStyle(
                                  color: ChannelTokens.action(context))),
                          onTap: _add),
                      for (final name in names.where((name) => name != '我'))
                        _row(name),
                    ]),
                  ] else ...[
                    if (!_removed)
                      Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: TextField(
                              onChanged: (value) =>
                                  setState(() => _query = value),
                              decoration: InputDecoration(
                                  hintText: channelText(
                                      context, '搜索订阅者', 'Search subscribers'),
                                  prefixIcon: const Icon(Icons.search),
                                  filled: true,
                                  fillColor: ChannelTokens.background(context),
                                  border: OutlineInputBorder(
                                      borderSide: BorderSide.none,
                                      borderRadius:
                                          BorderRadius.circular(10))))),
                    for (final name in names)
                      _removed || name == '我'
                          ? _row(name)
                          : Dismissible(
                              key: ValueKey(name),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                  color: Theme.of(context).colorScheme.error,
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.all(16),
                                  child: const Icon(Icons.delete_outline,
                                      color: AppTokens.onAccent)),
                              confirmDismiss: (_) async {
                                _selected
                                  ..clear()
                                  ..add(name);
                                await _remove();
                                return false;
                              },
                              child: _row(name)),
                    if (names.isEmpty)
                      ChannelEmpty(
                          title: channelText(
                              context,
                              _query.isEmpty ? '暂无订阅者' : '未找到匹配的订阅者',
                              'No subscribers'),
                          message: channelText(context, '订阅者会显示在这里',
                              'Subscribers will appear here.')),
                  ],
                ]));
      });
  Widget _row(String name) => ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
        title: Text(name),
        subtitle: Text(channelText(
            context,
            name == '我'
                ? '创建人'
                : _admins
                    ? '管理员 · 示例用户'
                    : '示例用户',
            name == '我'
                ? 'Owner'
                : _admins
                    ? 'Administrator · Example'
                    : 'Example user')),
        trailing: _removed
            ? TextButton(
                onPressed: () => widget.channel.update(() {
                      widget.channel.removedMembers.remove(name);
                      widget.channel.members.add(name);
                    }),
                child: Text(channelText(context, '恢复', 'Restore')))
            : _admins && name != '我'
                ? IconButton(
                    tooltip:
                        channelText(context, '撤销管理员', 'Remove administrator'),
                    onPressed: () => widget.channel.update(
                        () => widget.channel.administrators.remove(name)),
                    icon: const Icon(Icons.remove_circle_outline))
                : null,
      );
}
