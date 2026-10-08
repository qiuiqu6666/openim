import 'package:flutter/material.dart';
import '../sangong_scope.dart';
import '../support/sangong_ui.dart';
import '../support/settings_exports.dart';
import '../services/authorization/sangong_operation_scope.dart';
import '../profile/sangong_authorized_view.dart';

class SangongUserGroupEntry extends StatefulWidget {
  const SangongUserGroupEntry(
      {super.key,
      required this.imUserId,
      required this.groupName,
      required this.onChanged});
  final String imUserId;
  final String groupName;
  final VoidCallback onChanged;
  @override
  State<SangongUserGroupEntry> createState() => _SangongUserGroupEntryState();
}

class _SangongUserGroupEntryState extends State<SangongUserGroupEntry> {
  bool _busy = false;
  late final _runtime = SangongScope.read(context);
  late final _scope = SangongOperationScope.capture(
      _runtime.featureContext, _runtime.http.tenantId);
  bool get _current =>
      mounted &&
      _runtime.canManage &&
      _scope.matches(_runtime.featureContext, _runtime.http.tenantId);

  Future<void> _edit() async {
    if (!_current || _busy) return;
    final id = widget.imUserId;
    final value = await AppDialog.prompt(
        context: context,
        title: '积分分组',
        message: '填写分组名称；留空或填 0 表示取消分组。',
        initialValue: widget.groupName,
        placeholder: '例如：A组',
        allowEmpty: true,
        cancelText: '取消',
        confirmText: '保存',
        dialogWrapper: (_, child) => SangongAuthorizedView(
            runtime: _runtime,
            isCurrent: () => _current && widget.imUserId == id,
            child: child));
    if (value == null || !_current || widget.imUserId != id) return;
    setState(() => _busy = true);
    try {
      await _runtime.admin.setUserGroup(imUserId: id, group: value.trim());
      if (!mounted || !_current || widget.imUserId != id) return;
      widget.onChanged();
      ToastUtils.toast('积分分组已保存', context: context);
    } catch (error) {
      if (mounted && _current) {
        ToastUtils.toast(DioErrorMessage.forApp(error), context: context);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _current
      ? SettingsCell(
          title: '积分分组',
          value: _busy
              ? '保存中…'
              : widget.groupName.isEmpty
                  ? '未分组'
                  : widget.groupName,
          showDivider: false,
          onTap: _busy ? null : _edit)
      : const SizedBox.shrink();
}
