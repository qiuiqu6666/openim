import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
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
      this.fetchGroups});
  final String imUserId;
  final bool hasRebate;
  final Future<List<GroupInfo>> Function(List<String>)? fetchGroups;
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

  Future<String> _resolveGroupId(String input) async {
    // Group profiles display an @ prefix even when it is absent from the SDK ID.
    // Prefer an exact match; only use the display alias when IM confirms it.
    if (!input.startsWith('@') || input.length == 1) return input;
    final ids = [input, input.substring(1)];
    try {
      final groups = await (widget.fetchGroups?.call(ids) ??
          OpenIM.iMManager.groupManager.getGroupsInfo(groupIDList: ids));
      for (final id in ids) {
        if (groups.any((group) => group.groupID == id)) return id;
      }
    } catch (_) {
      // Keep the supplied ID if optional IM metadata cannot confirm an alias.
    }
    return input;
  }

  Widget _guardDialog(BuildContext dialogContext, Widget child) =>
      ListenableBuilder(
          listenable: _runtime,
          builder: (_, __) => _current
              ? child
              : CupertinoAlertDialog(title: const Text('游戏权限已变化'), actions: [
                  CupertinoDialogAction(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('关闭'))
                ]));

  Future<void> _edit({bool clear = false}) async {
    if (!_current || _saving || _loading || (!clear && !widget.hasRebate)) {
      return;
    }
    setState(() => _saving = true);
    try {
      String? groupId;
      if (clear) {
        final confirmed = await AppDialog.confirm(
            context: context,
            title: '清除代理群',
            message: '清除后，该用户将无法从原代理群进入三公代理。',
            dialogWrapper: _guardDialog);
        if (!_current || !confirmed) return;
      } else {
        final input = await AppDialog.prompt(
            context: context,
            title: '设置代理群',
            message: '可从群资料复制群 ID。一个代理群只对应一个厅；用户加入后可查看自己在本厅的代理和团队数据。',
            placeholder: '请输入群 ID',
            initialValue: _groupId ?? '',
            confirmText: '保存',
            maxLength: 128,
            dialogWrapper: _guardDialog);
        if (!_current || input == null) return;
        groupId = input.trim();
        if (groupId.isEmpty) return;
        groupId = await _resolveGroupId(groupId);
        if (!_current) return;
      }
      await _api.setUserGroup(_userId, groupId);
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
        : (_group?.groupName?.isNotEmpty == true ? _group!.groupName! : '已设置');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.groups_outlined),
          title: const Text('代理群'),
          subtitle: Text(_loading
              ? '正在加载…'
              : _error != null
                  ? '加载失败，请重试'
                  : _groupId == null
                      ? title
                      : '$title\n群 ID：$_groupId'),
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
