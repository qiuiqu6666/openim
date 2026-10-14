import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:openim_common/openim_common.dart';

import '../../../../core/server_nodes/node_endpoint.dart';
import '../../../../core/server_nodes/manual_node_switch_service.dart';
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
  String? _noticeNode;
  NodeSwitchFailure? _notice;

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
    if (_controller.testing) {
      return settingsText(context, zh: '测速中', en: 'Testing');
    }
    final value = _controller.hasManualTest
        ? _controller.testedAt
        : StartupNodeSelection.last?.checkedAt;
    if (value == null) {
      return settingsText(context, zh: '尚未测速', en: 'Not tested');
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  Future<void> _switchNode(NodeEndpoint node) async {
    setState(() {
      _notice = null;
      _noticeNode = null;
    });
    if (node.signature == NodeEndpoint.shield.signature) {
      await EasyLoading.showToast(
        settingsText(context,
            zh: '该节点仅在其他节点不可用时切换',
            en: 'This node is used only when the other nodes are unavailable.'),
        toastPosition: EasyLoadingToastPosition.center,
        duration: const Duration(seconds: 2),
        maskType: EasyLoadingMaskType.none,
        dismissOnTap: false,
      );
      return;
    }
    final failure = await _controller.switchTo(node);
    if (!mounted) return;
    setState(() {
      _notice = failure;
      _noticeNode = node.signature;
    });
  }

  String _noticeText(BuildContext context) {
    final (zh, en) = switch (_notice) {
      null => ('节点切换成功', 'Node switched'),
      NodeSwitchFailure.busy => (
          '正在通话或处理连接，请稍后切换',
          'A call or connection change is in progress. Try again shortly.'
        ),
      NodeSwitchFailure.unavailable => (
          '该节点暂不可用，已保留原连接',
          'This node is unavailable. Your connection is unchanged.'
        ),
      NodeSwitchFailure.sessionChanged => (
          '操作已取消，请稍后重试',
          'Operation cancelled. Please try again.'
        ),
      NodeSwitchFailure.connectionFailed => (
          '切换失败，已恢复原节点',
          'Switch failed. The previous node was restored.'
        ),
      NodeSwitchFailure.recoveryFailed => (
          '连接未恢复，请检查网络后重启 App',
          'Connection could not be restored. Check your network and restart the app.'
        ),
    };
    return settingsText(context, zh: zh, en: en);
  }

  Widget _nodeRow(BuildContext context, NodeEndpoint node, int index) {
    final dark = settingsIsDark(context);
    final selected = !_controller.connectionUnconfirmed &&
        node.signature == _controller.endpoint.signature;
    var status = NodeProbeStatus.unknown;
    int? latency;
    final checks = _controller.hasManualTest
        ? []
        : StartupNodeSelection.last?.checks ?? [];
    for (final check in checks) {
      if (check.endpoint.signature == node.signature) {
        status =
            check.available ? NodeProbeStatus.normal : NodeProbeStatus.abnormal;
        latency = check.latencyMs;
      }
    }
    final result = _controller.results[node.signature];
    if (result != null) {
      status = result.status;
      latency = result.latencyMs;
    }
    var label = status == NodeProbeStatus.normal
        ? '${settingsText(context, zh: '正常', en: 'OK')} (${latency}ms)'
        : settingsText(context,
            zh: status == NodeProbeStatus.abnormal ? '异常' : '未知',
            en: status == NodeProbeStatus.abnormal ? 'Abnormal' : 'Unknown');
    if (_controller.pending.contains(node.signature)) {
      status = NodeProbeStatus.unknown;
      label = settingsText(context, zh: '测速中', en: 'Testing');
    }
    if (_controller.switchingTo?.signature == node.signature) {
      status = NodeProbeStatus.unknown;
      label = settingsText(context, zh: '切换中', en: 'Switching');
    }
    final color = status == NodeProbeStatus.normal
        ? (dark ? AppTokens.successDark : AppTokens.success)
        : status == NodeProbeStatus.abnormal
            ? AppTokens.danger
            : AppTokens.textSecondary(dark: dark);
    return Semantics(
      key: ValueKey('node-row-$index'),
      selected: selected,
      child: InkWell(
        onTap: node.signature == NodeEndpoint.shield.signature
            ? () => _switchNode(node)
            : _controller.testing || _controller.switching || selected
                ? null
                : () => _switchNode(node),
        child: Container(
          constraints: BoxConstraints(
              minHeight: SettingsResponsive.listRowMinHeight(context)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(
                      settingsText(context,
                          zh: '节点${(index + 1).toString().padLeft(2, '0')}',
                          en: 'Node ${(index + 1).toString().padLeft(2, '0')}'),
                      style:
                          TextStyle(color: AppTokens.textPrimary(dark: dark)))),
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
            if (_notice != null && _noticeNode == node.signature)
              Padding(
                padding: const EdgeInsets.only(top: AppTokens.s2),
                child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _noticeText(context),
                      key: ValueKey('node-notice-$index'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTokens.textSecondary(dark: dark)),
                    )),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final sub = AppTokens.textSecondary(dark: dark);
          final nodes = _controller.nodes;
          return SettingsScaffold(
            embedded: widget.embedded,
            title: settingsText(context, zh: '节点切换', en: 'Node Switch'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(children: [
                  OutlinedButton.icon(
                    onPressed: _controller.testing || _controller.switching
                        ? null
                        : () {
                            setState(() {
                              _notice = null;
                              _noticeNode = null;
                            });
                            _controller.test();
                          },
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
                        zh: '点击节点01、02可切换并重新连接。节点03仅在其他节点不可用时自动切换。每次启动 App 时仍会自动检测并选择可用节点。\n\n手动测速会重新检测所有节点，不会自动切换连接。通话中请稍后切换。',
                        en: 'Tap node 01 or 02 to switch and reconnect. Node 03 is selected automatically only when the other nodes are unavailable. Each app launch still automatically selects an available node.\n\nSpeed Test checks every node without switching. Wait until your call ends before switching.'),
                    style: TextStyle(color: sub, fontSize: 12, height: 1.45)),
              ),
            ],
          );
        },
      );
}
