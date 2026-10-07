import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../../sangong_scope.dart';
import '../../services/authorization/sangong_operation_scope.dart';
import '../../support/sangong_ui.dart';
import '../../support/settings_exports.dart';
import '../data/sangong_agent_management_api.dart';

/// Uses the existing settings cells and confirmation flow from the group config.
class SangongAgentGroupsPage extends StatefulWidget {
  const SangongAgentGroupsPage({super.key});
  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(SangongPageRoute<void>(
          context: context,
          settings: const RouteSettings(name: 'sangong_agent_groups'),
          builder: (_) => const SangongAgentGroupsPage()));
  @override
  State<SangongAgentGroupsPage> createState() => _SangongAgentGroupsPageState();
}

class _SangongAgentGroupsPageState extends State<SangongAgentGroupsPage> {
  late final _runtime = SangongScope.read(context);
  late final _scope = SangongOperationScope.capture(
      _runtime.featureContext, _runtime.http.tenantId);
  late final _api = SangongAgentManagementApi(_runtime.http);
  final _input = TextEditingController();
  List<String> _groups = const [];
  bool _loading = true, _saving = false;
  String? _error;
  int _generation = 0;
  bool get _current =>
      mounted &&
      _runtime.canManage &&
      _runtime.canConfigure &&
      _scope.matches(_runtime.featureContext, _runtime.http.tenantId);

  @override
  void initState() {
    super.initState();
    // Capture the scope before the first network request.
    _scope;
    _load();
  }

  @override
  void dispose() {
    _generation++;
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted || !_current) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final groups = await _api.groups();
      if (mounted && _current && generation == _generation) {
        setState(() => _groups = groups);
      }
    } catch (e) {
      if (mounted && _current && generation == _generation) {
        setState(() => _error = DioErrorMessage.forApp(e));
      }
    } finally {
      if (mounted && _current && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _bind() async {
    if (!mounted || !_current || _saving || _loading) return;
    final id = _input.text.trim();
    if (id.isEmpty) {
      ToastUtils.toast('请填写代理群 ID', context: context);
      return;
    }
    setState(() => _saving = true);
    try {
      final confirmed = await AppDialog.confirm(
          context: context,
          title: '绑定独立代理群',
          message: '将代理群 $id 绑定到当前下注群 ${_scope.groupId}。该代理群只能归属一个下注群。',
          dialogWrapper: (dialogContext, child) =>
              _guard(child, dialogContext: dialogContext));
      if (!mounted || !_current || !confirmed) return;
      await _api.bind(id);
      if (!mounted || !_current) return;
      _input.clear();
      ToastUtils.toast('代理群已绑定', context: context);
      await _load();
    } catch (e) {
      if (mounted && _current) {
        ToastUtils.toast(DioErrorMessage.forApp(e), context: context);
      }
    } finally {
      if (mounted && _current) setState(() => _saving = false);
    }
  }

  Widget _guard(Widget child, {BuildContext? dialogContext}) =>
      ListenableBuilder(
          listenable:
              Listenable.merge([_runtime, _runtime.http.tenantIdListenable]),
          builder: (_, __) => _current
              ? child
              : dialogContext != null
                  ? CupertinoAlertDialog(
                      title: const Text('游戏权限已变化'),
                      content: const Text('请返回当前群后重新进入'),
                      actions: [
                          CupertinoDialogAction(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(false),
                              child: const Text('关闭'))
                        ])
                  : const SettingsScaffold(
                      title: '代理群绑定', children: [Text('当前游戏权限已变化，请重新进入')]));

  @override
  Widget build(BuildContext context) => _guard(SettingsScaffold(
          title: '代理群绑定',
          dismissKeyboardOnOutsideTap: true,
          children: [
            SettingsGroup(children: [
              SettingsCell(
                  title: '下注群',
                  value: _scope.groupId,
                  showArrow: false,
                  showDivider: false)
            ]),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              SettingsGroup(children: [
                SettingsCell(
                    title: _error!,
                    value: '重试',
                    onTap: _load,
                    showDivider: false)
              ]),
            if (!_loading && _error == null)
              SettingsGroup(children: [
                if (_groups.isEmpty)
                  const SettingsCell(
                      title: '尚未绑定代理群', showArrow: false, showDivider: false),
                for (final id in _groups)
                  SettingsCell(title: '已绑定代理群', value: id, showArrow: false),
              ]),
            SettingsGroup(children: [
              SettingsInputCell(
                  label: '代理群 ID',
                  hint: '填写独立代理群的群 ID',
                  controller: _input,
                  readOnly: _saving)
            ]),
            SettingsPrimaryButton(
                text: _saving ? '绑定中…' : '绑定代理群',
                onPressed: _saving || _loading ? () {} : _bind),
          ]));
}
