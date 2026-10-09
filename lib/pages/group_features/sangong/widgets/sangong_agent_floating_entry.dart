// Adapted from 99chat d7c3c65, Apache-2.0. See README.md and LICENSE-99chat.
import 'package:flutter/material.dart';
import 'package:openim/pages/group_features/sangong/widgets/agent_rebate_floating_entry.dart';
import 'package:openim/pages/group_features/sangong/support/sangong_ui.dart';

/// 三公代理专用浮窗：查 / 团 / 个 / 隐。
class SangongAgentFloatingEntry extends StatelessWidget {
  const SangongAgentFloatingEntry({
    super.key,
    required this.theme,
    required this.conversationId,
    required this.onOpenQuery,
    required this.onOpenTeam,
    required this.onOpenPersonal,
  });

  final SangongFloatTheme theme;
  final String conversationId;
  final VoidCallback onOpenQuery;
  final VoidCallback onOpenTeam;
  final VoidCallback onOpenPersonal;

  @override
  Widget build(BuildContext context) {
    return AgentRebateFloatingEntry(
      theme: theme,
      conversationId: conversationId,
      variant: AgentRebateFloatingVariant.sangong,
      defaultBottom: 500,
      defaultExpanded: true,
      onOpenDescendants: onOpenQuery,
      onOpenRebate: onOpenTeam,
      onOpenHistory: onOpenPersonal,
    );
  }
}
