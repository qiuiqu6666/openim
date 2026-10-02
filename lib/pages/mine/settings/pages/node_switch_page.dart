import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';

class NodeSwitchPage extends StatefulWidget {
  const NodeSwitchPage({
    super.key,
    required this.store,
    required this.service,
    this.embedded = false,
  });

  final SettingsDraftStore store;
  final SettingsService service;
  final bool embedded;

  @override
  State<NodeSwitchPage> createState() => _NodeSwitchPageState();
}

class _NodeSwitchPageState extends State<NodeSwitchPage> {
  static const _nodes = <_NodeDefinition>[
    _NodeDefinition(id: 'cn', name: '节点01(CN)'),
    _NodeDefinition(id: 'apiios', name: '节点02(US)'),
  ];

  bool _testing = false;
  bool _selecting = false;

  String get _selectedId => widget.store.selectedNodeId ?? 'cn';

  Future<void> _test() async {
    if (_testing) return;
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '节点测速', en: 'Node speed test'),
      );
      return;
    }
    setState(() => _testing = true);
    try {
      await widget.service.testNodes();
      widget.store.markNodeTested();
      if (!mounted) return;
      showSettingsMessage(
        context,
        settingsText(context, zh: '测速完成', en: 'Speed test completed'),
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _select(String nodeId) async {
    if (_selecting || nodeId == _selectedId) return;
    if (!widget.service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '节点切换', en: 'Node switching'),
      );
      return;
    }
    setState(() => _selecting = true);
    try {
      await widget.service.selectNode(nodeId);
      widget.store.selectNode(nodeId);
    } finally {
      if (mounted) setState(() => _selecting = false);
    }
  }

  String _time(BuildContext context) {
    final value = widget.store.nodeLastTestAt;
    if (value == null) {
      return settingsText(context, zh: '尚未测速', en: 'Not tested');
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final sub = AppTokens.textSecondary(dark: dark);
          final text = AppTokens.textPrimary(dark: dark);

          return SettingsScaffold(
            embedded: widget.embedded,
            title: settingsText(context, zh: '节点切换', en: 'Node Switch'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testing ? null : _test,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.accent,
                        side: BorderSide(
                          color: AppTokens.accent.withOpacity(0.7),
                        ),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                      icon: _testing
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(AppTokens.accent),
                              ),
                            )
                          : const Icon(Icons.speed_rounded, size: 18),
                      label: Text(
                        settingsText(context, zh: '手动测速', en: 'Speed Test'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          settingsText(context, zh: '测速时间', en: 'Tested at'),
                          style: TextStyle(color: sub, fontSize: 11),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _time(context),
                          style: TextStyle(color: sub, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SettingsGroup(
                children: [
                  for (var i = 0; i < _nodes.length; i++)
                    _NodeRow(
                      name: _nodes[i].name,
                      selected: _selectedId == _nodes[i].id,
                      showDivider: i != _nodes.length - 1,
                      textColor: text,
                      subColor: sub,
                      onTap: _selecting ? null : () => _select(_nodes[i].id),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                child: Text(
                  settingsText(
                    context,
                    zh: '加载失败或速度慢时，可手动切换节点提升体验。\n\n状态说明：正常 / 异常 / 未知。可切换 4G、5G、Wi‑Fi 后重新测速，选择延迟更低的节点。',
                    en: 'If loading fails or feels slow, switch nodes manually.\n\nStatus: OK / Abnormal / Unknown. Retest on 4G, 5G, or Wi‑Fi and pick the lower-latency node.',
                  ),
                  style: TextStyle(color: sub, fontSize: 12, height: 1.45),
                ),
              ),
            ],
          );
        },
      );
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.name,
    required this.selected,
    required this.showDivider,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  final String name;
  final bool selected;
  final bool showDivider;
  final Color textColor;
  final Color subColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    final desktop = SettingsResponsive.isDesktop(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: desktop ? AppTokens.accent.withOpacity(0.06) : null,
        mouseCursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        child: Container(
          constraints: BoxConstraints(
            minHeight: SettingsResponsive.listRowMinHeight(context),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom: BorderSide(
                      color: AppTokens.border(dark: dark),
                      width: 0.6,
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontSize: desktop ? 15 : 16),
                ),
              ),
              Icon(Icons.circle, size: 8, color: subColor),
              const SizedBox(width: 6),
              Text(
                settingsText(context, zh: '未知', en: 'Unknown'),
                style: TextStyle(
                  color: subColor,
                  fontSize: desktop ? 13 : 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 22,
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppTokens.accent,
                        size: 22,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NodeDefinition {
  const _NodeDefinition({required this.id, required this.name});
  final String id;
  final String name;
}
