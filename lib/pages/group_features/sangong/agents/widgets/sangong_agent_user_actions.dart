import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../sangong_scope.dart';
import '../../services/account_identity/sangong_account_identity_resolver.dart';
import '../../services/authorization/sangong_operation_scope.dart';
import '../../support/sangong_ui.dart';
import '../data/sangong_agent_management_api.dart';

/// Management flows stay outside the account-report and agent-detail pages.
class SangongAgentUserActions extends StatefulWidget {
  const SangongAgentUserActions(
      {super.key,
      required this.userId,
      required this.imUserId,
      required this.nickname,
      required this.rebatePct,
      required this.parentUserId,
      required this.onChanged,
      this.agent = false});
  final int userId, parentUserId;
  final String imUserId, nickname;
  final num rebatePct;
  final bool agent;
  final Future<void> Function() onChanged;
  @override
  State<SangongAgentUserActions> createState() =>
      _SangongAgentUserActionsState();
}

class _SangongAgentUserActionsState extends State<SangongAgentUserActions> {
  late final _runtime = SangongScope.read(context);
  late final _scope = SangongOperationScope.capture(
      _runtime.featureContext, _runtime.http.tenantId);
  late final _userId = widget.userId;
  late final _imUserId = widget.imUserId;
  late final _api =
      SangongAgentManagementApi(_runtime.http, agent: widget.agent);
  late final _identity = SangongAccountIdentityResolver(
      isCurrent: () => _current,
      scopeToken: () => SangongOperationScope.capture(
              _runtime.featureContext, _runtime.http.tenantId)
          .token);
  bool _busy = false;
  bool get _current =>
      mounted &&
      _userId > 0 &&
      widget.userId == _userId &&
      widget.imUserId == _imUserId &&
      _runtime.isCurrent &&
      _scope.matches(_runtime.featureContext, _runtime.http.tenantId) &&
      (widget.agent
          ? _runtime.canOpenAgent &&
              widget.parentUserId > 0 &&
              widget.parentUserId ==
                  int.tryParse(_runtime.agentContext?.userId ?? '')
          : _runtime.canManage);

  @override
  void initState() {
    super.initState();
    _scope;
    _userId;
    _imUserId;
  }

  @override
  void dispose() {
    _identity.close();
    super.dispose();
  }

  Widget _dialog(BuildContext dialogContext, Widget child) => ListenableBuilder(
      listenable:
          Listenable.merge([_runtime, _runtime.http.tenantIdListenable]),
      builder: (_, __) => _current
          ? child
          : CupertinoAlertDialog(
              title: const Text('游戏权限已变化'),
              content: const Text('请返回当前群后重新进入'),
              actions: [
                  CupertinoDialogAction(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      child: const Text('关闭'))
                ]));

  Future<void> _run(Future<bool> Function() action) async {
    if (!mounted || !_current || _busy) return;
    setState(() => _busy = true);
    try {
      final changed = await action();
      if (!mounted || !_current || !changed) return;
      ToastUtils.toast('已保存', context: context);
      await widget.onChanged();
    } catch (e) {
      if (mounted && _current) {
        ToastUtils.toast(DioErrorMessage.forApp(e), context: context);
      }
    } finally {
      if (mounted && _current) setState(() => _busy = false);
    }
  }

  String get _name =>
      widget.nickname.trim().isEmpty ? widget.imUserId : widget.nickname;

  Future<bool> _editRate() async {
    final input = await AppDialog.prompt(
        context: context,
        title: '设置返水比例',
        message: '$_name\n填写百分比，最多四位小数。下级比例不能超过上级。',
        initialValue: widget.rebatePct.toStringAsFixed(4),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        maxLength: 8,
        dialogWrapper: _dialog);
    if (!mounted || !_current || input == null) return false;
    final rate = sangongRebateRate(input);
    final confirmed = await AppDialog.confirm(
        context: context,
        title: '确认返水比例',
        message: '将 $_name（${widget.imUserId}）在当前下注群的返水比例设为 $rate%。',
        dialogWrapper: _dialog);
    if (!mounted || !_current || !confirmed) return false;
    await _api.setRate(_userId, rate);
    return true;
  }

  Future<bool> _attach() async {
    if (widget.agent || widget.parentUserId > 0) return false;
    final input = await AppDialog.prompt(
        context: context,
        title: '设置上级代理',
        message: '填写上级的公开账号名或 IM 用户 ID。上级须属于当前下注群；已有账务或下级的成员不能改变归属。',
        placeholder: '公开账号名或 IM 用户 ID',
        maxLength: 128,
        dialogWrapper: _dialog);
    if (!mounted || !_current || input == null) return false;
    final imId = await _identity.resolve(input);
    if (!mounted || !_current || imId == null) return false;
    final detail = await _runtime.admin.fetchUserDetail(imId);
    if (!mounted || !_current) return false;
    final parent = detail['user'];
    if (detail['exists'] != true ||
        parent is! Map ||
        parent['userId'] is! int) {
      throw StateError('该上级尚未加入当前下注群，请先添加成员');
    }
    final parentId = parent['userId'] as int;
    if (parentId == _userId) throw StateError('不能将自己设为上级');
    final parentName = parent['nickname']?.toString() ?? imId;
    final confirmed = await AppDialog.confirm(
        context: context,
        title: '确认上级代理',
        message:
            '将 $_name（${widget.imUserId}）挂靠到 $parentName（$imId）。此关系仅适用于当前下注群。',
        dialogWrapper: _dialog);
    if (!mounted || !_current || !confirmed) return false;
    await _api.attach(_userId, parentId);
    return true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable:
          Listenable.merge([_runtime, _runtime.http.tenantIdListenable]),
      builder: (_, __) => !_current
          ? const SizedBox.shrink()
          : Wrap(children: [
              TextButton.icon(
                  onPressed: _busy ? null : () => _run(_editRate),
                  icon: const Icon(Icons.percent_outlined),
                  label: Text(_busy ? '处理中…' : '设置返水')),
              if (!widget.agent && widget.parentUserId == 0)
                TextButton.icon(
                    onPressed: _busy ? null : () => _run(_attach),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('设置上级')),
            ]));
}
