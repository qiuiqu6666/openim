import 'package:flutter/material.dart';
import '../models/group_feature_context.dart';
import 'agent/pages/agent_current_page.dart';
import 'agent/pages/agent_descendants_page.dart';
import 'agent/pages/agent_history_page.dart';
import 'pages/mark_six_page.dart';

/// Public, credential-neutral entry points used by the chat/menu coordinator.
class MarkSixModule {
  MarkSixModule._();
  static Future<void> openDrawHistory(
          BuildContext context, GroupFeatureContext featureContext) =>
      _open(context, featureContext,
          MarkSixPage(featureContext: featureContext), 'mark_six_draw_history');
  static Future<void> openAgent(
          BuildContext context, GroupFeatureContext featureContext) =>
      _open(
          context,
          featureContext,
          AgentDescendantsPage(featureContext: featureContext),
          'mark_six_agent');
  static Future<void> openCurrentRebate(
          BuildContext context, GroupFeatureContext featureContext) =>
      _open(
          context,
          featureContext,
          AgentCurrentPage(featureContext: featureContext),
          'mark_six_rebate_current');
  static Future<void> openRebateHistory(
          BuildContext context, GroupFeatureContext featureContext) =>
      _open(
          context,
          featureContext,
          AgentHistoryPage(featureContext: featureContext),
          'mark_six_rebate_history');
  static Future<void> _open(BuildContext context,
      GroupFeatureContext featureContext, Widget page, String name) async {
    if (!featureContext.sessionCurrent() || !context.mounted) return;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
        settings: RouteSettings(name: name), builder: (_) => page));
  }
}
