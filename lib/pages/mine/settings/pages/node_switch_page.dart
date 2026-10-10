import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

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
    final value = _controller.testedAt;
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

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final sub = AppTokens.textSecondary(dark: dark);
          final statusColor = _controller.status == NodeProbeStatus.normal
              ? const Color(0xFF34C759)
              : _controller.status == NodeProbeStatus.abnormal
                  ? AppTokens.danger
                  : sub;
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
                Container(
                  constraints: BoxConstraints(
                      minHeight: SettingsResponsive.listRowMinHeight(context)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            settingsText(context, zh: '节点01', en: 'Node 01'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: AppTokens.textPrimary(dark: dark),
                                fontSize: SettingsResponsive.isDesktop(context)
                                    ? 15
                                    : 16,
                                fontWeight: FontWeight.w400))),
                    Icon(Icons.circle, size: 8, color: statusColor),
                    const SizedBox(width: 6),
                    Semantics(
                        liveRegion: true,
                        child: Text(_status(context),
                            style: TextStyle(
                                color: statusColor,
                                fontSize: SettingsResponsive.isDesktop(context)
                                    ? 13
                                    : 14,
                                fontWeight: FontWeight.w500))),
                    const SizedBox(width: 10),
                    const SizedBox(
                        width: 22,
                        child: Icon(Icons.check_rounded,
                            color: AppTokens.accent, size: 22)),
                  ]),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Text(
                    settingsText(context,
                        zh: '加载失败或速度慢时，可重新测速查看节点状态。\n\n状态说明：正常 / 异常 / 未知。可切换 4G、5G、Wi-Fi 后重新测速。',
                        en: 'If loading fails or feels slow, retest the node.\n\nStatus: OK / Abnormal / Unknown. Retest on 4G, 5G or Wi-Fi.'),
                    style: TextStyle(color: sub, fontSize: 12, height: 1.45)),
              ),
            ],
          );
        },
      );
}
