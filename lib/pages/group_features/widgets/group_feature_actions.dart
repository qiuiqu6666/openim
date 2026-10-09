import '../sangong/services/authorization/sangong_access_policy.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import '../data/group_feature_store.dart';
import '../models/group_feature_context.dart';
import '../live/group_live_module.dart';
import '../sangong/sangong_module.dart';
import '../mark_six/mark_six.dart';
import 'group_feature_tokens.dart';

class GroupFeatureActions {
  static List<ToolboxItemInfo> items(
      BuildContext context, GroupFeatureContext feature,
      {VoidCallback? onLiveStateChanged}) {
    if (!feature.sessionCurrent()) return const [];
    final games = feature.features, caps = feature.capabilities;
    final privileged = feature.privilege
        .allows(userID: feature.currentUserID, baseUrl: feature.api.baseUrl);
    final sangongScope = context
        .getElementForInheritedWidgetOfExactType<SangongScope>()
        ?.widget as SangongScope?;
    final sangongRuntime = sangongScope?.notifier;
    return [
      if (feature.isGroupAdmin ||
          caps.live.canConfigure ||
          caps.live.canManage ||
          caps.live.canPush)
        ToolboxItemInfo(
            id: 'group_live',
            text: '群直播',
            icon: '',
            symbol: Icons.live_tv_rounded,
            onTap: () => GroupLiveModule.openManage(context,
                featureContext: feature,
                onStateChanged: (_) => onLiveStateChanged?.call())),
      if (privileged)
        ToolboxItemInfo(
            text: '三公运营',
            icon: '',
            symbol: Icons.sports_esports_outlined,
            onTap: () => SangongModule.openManage(context,
                featureContext: feature, runtime: sangongRuntime)),
      if (sangongAgentEntryVisible(feature))
        ToolboxItemInfo(
            text: '三公代理',
            icon: '',
            symbol: Icons.groups_outlined,
            onTap: () => SangongModule.openAgent(context,
                featureContext: feature, runtime: sangongRuntime)),
      if (feature.showMarkSixDrawHistory)
        ToolboxItemInfo(
            text: '开奖记录',
            icon: '',
            symbol: Icons.history_rounded,
            onTap: () => MarkSixModule.openDrawHistory(context, feature)),
      if (games.markSix.enabled &&
          games.markSix.agentEntry &&
          caps.markSix.canOpenAgent)
        ToolboxItemInfo(
            text: '六合彩代理',
            icon: '',
            symbol: Icons.account_tree_outlined,
            onTap: () => MarkSixModule.openAgent(context, feature)),
      if (games.markSix.enabled &&
          games.markSix.rebateHistoryEntry &&
          caps.markSix.canViewRebateHistory)
        ToolboxItemInfo(
            text: '反水历史',
            icon: '',
            symbol: Icons.receipt_long_outlined,
            onTap: () => MarkSixModule.openRebateHistory(context, feature)),
    ];
  }

  static Future<void> open(BuildContext context, GroupFeatureStore store,
      GroupFeatureContext Function() readContext) async {
    final hostContext = context;
    final original = readContext();
    if (!original.sessionCurrent()) return;
    Future<void> refresh({bool force = false}) async {
      final feature = readContext();
      if (!feature.sessionCurrent()) return;
      await Future.wait([
        feature.privilege.refresh(),
        store.loadCapabilities(feature.groupID, force: force),
      ]);
    }

    await refresh();
    if (!context.mounted || !original.sessionCurrent()) return;
    final current = readContext();
    if (!current.sessionCurrent() ||
        current.groupID != original.groupID ||
        current.currentUserID != original.currentUserID ||
        !identical(current.api, original.api) ||
        !identical(current.privilege, original.privilege)) {
      return;
    }
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: GroupFeatureTokens.of(context).surface,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (sheetContext) => SafeArea(
            child: ListenableBuilder(
                listenable: store,
                builder: (context, _) {
                  final feature = readContext();
                  final actions = hostContext.mounted
                      ? items(hostContext, feature,
                          onLiveStateChanged: () =>
                              store.refreshGroup(feature.groupID))
                      : <ToolboxItemInfo>[];
                  final error = store.capabilityError(feature.groupID);
                  final tokens = GroupFeatureTokens.of(context);
                  return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('群功能',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.text)),
                            const SizedBox(height: 12),
                            for (final item in actions)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading:
                                      Icon(item.symbol, color: tokens.primary),
                                  title:
                                      Text(item.text, style: tokens.pageText),
                                  trailing: Icon(Icons.chevron_right,
                                      color: tokens.secondary),
                                  onTap: () {
                                    Navigator.pop(sheetContext);
                                    item.onTap?.call();
                                  }),
                            if (error != null)
                              ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(error.message,
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: tokens.secondary)),
                                  trailing: TextButton(
                                      onPressed: store.capabilitiesLoading(
                                              feature.groupID)
                                          ? null
                                          : () => refresh(force: true),
                                      child: const Text('重试'))),
                            if (actions.isEmpty && error == null)
                              Padding(
                                  padding: const EdgeInsets.all(20),
                                  child: Text('此群暂无可用功能',
                                      textAlign: TextAlign.center,
                                      style:
                                          TextStyle(color: tokens.secondary))),
                          ]));
                })));
  }
}
