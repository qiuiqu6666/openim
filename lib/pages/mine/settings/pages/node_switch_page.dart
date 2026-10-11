import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../core/server_nodes/node_endpoint.dart';
import '../../../../core/server_nodes/startup_node_selection.dart';
import '../node_switch/node_probe_controller.dart';
import '../settings_draft_store.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class NodeSwitchPage extends StatefulWidget {
  const NodeSwitchPage({
    super.key,
    required this.store,
    required this.service,
    this.embedded = false,
    this.controller,
  });

  final SettingsDraftStore store;
  final SettingsService service;
  final bool embedded;
  final NodeProbeController? controller;

  @override
  State<NodeSwitchPage> createState() => _NodeSwitchPageState();
}

class _NodeSwitchPageState extends State<NodeSwitchPage> {
  late final NodeProbeController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? NodeProbeController();
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  String _time(BuildContext context) {
    final value = _controller.testedAt ?? StartupNodeSelection.last?.checkedAt;
    if (value == null) {
      return settingsText(context, zh: '尚未测速', en: 'Not tested');
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _status(BuildContext context) {
    if (_controller.testing) {
      return settingsText(context, zh: '测速中', en: 'Testing');
    }
    switch (_controller.status) {
      case NodeProbeStatus.unknown:
        return settingsText(context, zh: '未知', en: 'Unknown');
      case NodeProbeStatus.normal:
        return '${settingsText(context, zh: '正常', en: 'OK')} (${_controller.latencyMs}ms)';
      case NodeProbeStatus.abnormal:
        return settingsText(context, zh: '异常', en: 'Abnormal');
    }
  }

  Widget _nodeRow(BuildContext context, NodeEndpoint node, int index) {
    final dark = settingsIsDark(context);
    final selected = node.signature == _controller.endpoint.signature;
    var status = NodeProbeStatus.unknown;
    int? latency;
    final checks = StartupNodeSelection.last?.checks ?? [];
    for (final check in checks) {
      if (check.endpoint.signature == node.signature) {
        status =
            check.available ? NodeProbeStatus.normal : NodeProbeStatus.abnormal;
        latency = check.latencyMs;
      }
    }
    var label = status == NodeProbeStatus.normal
        ? '${settingsText(context, zh: '正常', en: 'OK')} (${latency}ms)'
        : settingsText(context,
            zh: status == NodeProbeStatus.abnormal ? '异常' : '未知',
            en: status == NodeProbeStatus.abnormal ? 'Abnormal' : 'Unknown');
    if (selected && (_controller.testing || _controller.testedAt != null)) {
      status = _controller.status;
      label = _status(context);
    }
    final color = status == NodeProbeStatus.normal
        ? (dark ? AppTokens.successDark : AppTokens.success)
        : status == NodeProbeStatus.abnormal
            ? AppTokens.danger
            : AppTokens.textSecondary(dark: dark);
    return Semantics(
      selected: selected,
      child: Container(
        constraints: BoxConstraints(
            minHeight: SettingsResponsive.listRowMinHeight(context)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
              child: Text(
                  settingsText(context,
                      zh: '节点${(index + 1).toString().padLeft(2, '0')}',
                      en: 'Node ${(index + 1).toString().padLeft(2, '0')}'),
                  style: TextStyle(color: AppTokens.textPrimary(dark: dark)))),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              Icon(Icons.circle, size: 8, color: color),
              const SizedBox(width: 6),
              Flexible(child: Text(label, style: TextStyle(color: color))),
              const SizedBox(width: 10),
              SizedBox(
                  width: 22,
                  child: selected
                      ? const Icon(Icons.check_rounded,
                          color: AppTokens.accent, size: 22)
                      : null),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final sub = AppTokens.textSecondary(dark: dark);
          final nodes = NodeEndpoint.candidates(_controller.endpoint);
          return SettingsScaffold(
            embedded: widget.embedded,
            title: settingsText(context, zh: '节点切换', en: 'Node Switch'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(children: [
                  OutlinedButton.icon(
                    onPressed: _controller.testing ? null : _controller.test,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.accent,
                        side: BorderSide(
                            color: AppTokens.accent.withValues(alpha: .7)),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8)),
                    icon: _controller.testing
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTokens.accent))
                        : const Icon(Icons.speed_rounded,
                            size: 18, color: AppTokens.accent),
                    label: Text(
                        settingsText(context, zh: '手动测速', en: 'Speed Test'),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppTokens.accent)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                        Text(settingsText(context, zh: '测速时间', en: 'Tested at'),
                            style: TextStyle(color: sub, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(_time(context),
                            textAlign: TextAlign.end,
                            style: TextStyle(color: sub, fontSize: 12)),
                      ])),
                ]),
              ),
              SettingsGroup(children: [
                for (var i = 0; i < nodes.length; i++)
                  _nodeRow(context, nodes[i], i),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Text(
                    settingsText(context,
                        zh: '每次启动 App 时自动检测并选择可用节点，使用中保持连接稳定。\n\n可手动测速查看当前节点状态；下次启动时会重新自动选择。',
                        en: 'A working node is selected automatically at each app launch. The connection stays unchanged during use.\n\nRetest the current node manually, or relaunch to select again.'),
                    style: TextStyle(color: sub, fontSize: 12, height: 1.45)),
              ),
            ],
          );
        },
      );
}
