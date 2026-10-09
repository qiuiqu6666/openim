import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import '../../../../contacts/group_list/group_list_logic.dart';
import '../../../../contacts/group_list/group_list_view.dart';
import '../../sangong_scope.dart';
import '../../services/authorization/sangong_operation_scope.dart';
import '../../support/sangong_ui.dart';
import '../data/sangong_agent_management_api.dart';

/// Owns the user's group assignment independently of report pagination.
class SangongUserAgentGroupEntry extends StatefulWidget {
  const SangongUserAgentGroupEntry(
      {super.key,
      required this.imUserId,
      required this.hasRebate,
      this.fetchGroups,
      this.pickGroup});
  final String imUserId;
  final bool hasRebate;
  final Future<List<GroupInfo>> Function(List<String>)? fetchGroups;
  final Future<GroupInfo?> Function(BuildContext, List<String>)? pickGroup;
  @override
  State<SangongUserAgentGroupEntry> createState() =>
      _SangongUserAgentGroupEntryState();
}

class _SangongUserAgentGroupEntryState
    extends State<SangongUserAgentGroupEntry> {
  late final _runtime = SangongScope.read(context);
  late final _scope = SangongOperationScope.capture(
      _runtime.featureContext, _runtime.http.tenantId);
  late final _userId = widget.imUserId;
  late final _api = SangongAgentManagementApi(_runtime.http);
  String? _groupId, _error;
  GroupInfo? _group;
  bool _loading = true, _saving = false;
  int _generation = 0;
  bool get _current =>
      mounted &&
      widget.imUserId == _userId &&
      _runtime.canManage &&
      _scope.matches(_runtime.featureContext, _runtime.http.tenantId);

  @override
  void initState() {
    super.initState();
    _runtime.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _generation++;
    _runtime.removeListener(_changed);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (!mounted || !_current) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = await _api.userGroup(_userId);
      if (!_current || generation != _generation) return;
      GroupInfo? group;
      if (id != null) {
        try {
          final groups = await (widget.fetchGroups?.call([id]) ??
              OpenIM.iMManager.groupManager.getGroupsInfo(groupIDList: [id]));
          for (final item in groups) {
            if (item.groupID == id) group = item;
          }
        } catch (_) {
          // IM display metadata is optional; the confirmed binding must stay
          // editable even if the group name is temporarily unavailable.
        }
      }
      if (!_current || generation != _generation) return;
      setState(() {
        _groupId = id;
        _group = group;
      });
    } catch (error) {
      if (_current && generation == _generation) {
        setState(() => _error = DioErrorMessage.forApp(error));
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<GroupInfo?> _select(List<String> ids) async {
    if (widget.pickGroup != null) return widget.pickGroup!(context, ids);
    final controller = GroupListLogic();
    controller.onInit();
    try {
      return await Navigator.of(context).push<GroupInfo>(SangongPageRoute(
          context: context,
          builder: (page) => GroupListPage(
              logic: controller,
              title: '选择代理群',
              allowedGroupIDs: ids.toSet(),
              disabledReason: '未绑定当前下注群',
              onSelected: (group) => Navigator.of(page).pop(group))));
    } finally {
      controller.onClose();
    }
  }

  Widget _guardDialog(BuildContext dialogContext, Widget child) =>
      ListenableBuilder(
          listenable: _runtime,
          builder: (_, __) => _current
              ? child
              : CupertinoAlertDialog(title: const Text('游戏权限已变化'), actions: [
                  CupertinoDialogAction(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('关闭'))
                ]));

  Future<void> _edit({bool clear = false}) async {
    if (!_current || _saving || _loading || (!clear && !widget.hasRebate)) {
      return;
    }
    setState(() => _saving = true);
    try {
      GroupInfo? selected;
      if (!clear) {
        final ids = await _api.groups();
        if (!mounted || !_current) return;
        if (ids.isEmpty) {
          ToastUtils.toast('请先在代理群绑定中添加当前下注群的代理群', context: context);
          return;
        }
        selected = await _select(ids);
        if (!mounted || !_current || selected == null) return;
        if (!ids.contains(selected.groupID)) {
          throw StateError('请选择已绑定当前下注群的代理群');
        }
      }
      if (!mounted || !_current) return;
      final confirmed = await AppDialog.confirm(
          context: context,
          title: clear ? '清除代理群' : '设置代理群',
          message: clear
              ? '清除后，该用户将无法从原代理群进入三公代理。'
              : '设置为“${selected!.groupName?.isNotEmpty == true ? selected.groupName : '所选群聊'}”。用户加入该群后，可进入三公代理查看自己的数据。',
          dialogWrapper: _guardDialog);
      if (!_current || !confirmed) return;
      await _api.setUserGroup(_userId, clear ? null : selected!.groupID);
      if (!mounted || !_current) return;
      await _load();
      if (mounted && _current) ToastUtils.toast('已保存', context: context);
    } catch (error) {
      if (mounted && _current) {
        ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_current) return const SizedBox.shrink();
    final title = _groupId == null
        ? '未设置'
        : (_group?.groupName?.isNotEmpty == true
            ? _group!.groupName!
            : '已设置（群名暂未获取）');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.groups_outlined),
          title: const Text('代理群'),
          subtitle: Text(_loading
              ? '正在加载…'
              : _error != null
                  ? '加载失败，请重试'
                  : title),
          trailing: _error != null
              ? IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
              : TextButton(
                  onPressed:
                      _loading || _saving || !widget.hasRebate ? null : _edit,
                  child: Text(_saving
                      ? '保存中…'
                      : _groupId == null
                          ? '设置'
                          : '更换'))),
      if (!widget.hasRebate)
        Text('返水比例大于 0 时可设置代理群', style: Theme.of(context).textTheme.bodySmall),
      if (_groupId != null && !_loading && _error == null)
        TextButton(
            onPressed: _saving ? null : () => _edit(clear: true),
            child: const Text('清除绑定')),
    ]);
  }
}
