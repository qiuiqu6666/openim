import 'package:flutter/material.dart';
import 'package:flutter_openim_sdk/flutter_openim_sdk.dart';
import 'package:get/get.dart';
import 'package:openim_common/openim_common.dart';
import '../settings/widgets/settings_widgets.dart';
import 'blacklist_logic.dart';

class BlacklistPage extends StatelessWidget {
  BlacklistPage({super.key});
  final logic = Get.find<BlacklistLogic>();
  String text(BuildContext context, String zh, String en) =>
      settingsText(context, zh: zh, en: en);
  Future<void> _remove(BuildContext context, BlacklistInfo info) async {
    final confirmed = await showSettingsActionSheet<bool>(context,
        title: text(
            context, '将该联系人移出黑名单？', 'Remove this contact from the blacklist?'),
        actions: [
          SettingsAction(text(context, '移出黑名单', 'Remove from Blacklist'), true)
        ]);
    if (confirmed != true || !context.mounted) return;
    try {
      final removed = await logic.remove(info);
      if (removed && context.mounted) {
        showSettingsMessage(
            context, text(context, '已移出黑名单', 'Removed from blacklist'));
      }
    } catch (error) {
      if (context.mounted) {
        showSettingsError(context, error,
            text(context, '移除失败，请重试', 'Could not remove. Please retry.'));
      }
    }
  }

  @override
  Widget build(BuildContext context) => SettingsScaffold(
        title: text(context, '黑名单', 'Blacklist'),
        body: Obx(() {
          if (logic.loading.value && logic.blacklist.isEmpty) {
            return Center(child: LoadingView.indicator());
          }
          if (logic.failed.value && logic.blacklist.isEmpty) {
            return SettingsEmptyState(
                icon: Icons.cloud_off_outlined,
                title: text(context, '黑名单加载失败', 'Could not load blacklist'),
                actionLabel: text(context, '重新加载', 'Retry'),
                onAction: logic.loadBlacklist);
          }
          if (logic.blacklist.isEmpty) {
            return SettingsEmptyState(
                icon: Icons.person_off_outlined,
                title: text(context, '暂无黑名单联系人', 'No blocked contacts'),
                description: text(context, '加入黑名单的联系人会显示在这里',
                    'Blocked contacts will appear here'));
          }
          return RefreshIndicator(
              onRefresh: logic.loadBlacklist,
              child: ListView(
                  padding: const EdgeInsets.all(AppTokens.s4),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    if (logic.failed.value)
                      TextButton(
                          onPressed: logic.loadBlacklist,
                          child: Text(text(
                              context, '刷新失败，点击重试', 'Refresh failed. Retry'))),
                    SettingsGroup(margin: EdgeInsets.zero, children: [
                      for (final info in logic.blacklist)
                        Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppTokens.s5,
                                vertical: AppTokens.s4),
                            decoration: BoxDecoration(
                              border: info == logic.blacklist.last
                                  ? null
                                  : Border(
                                      bottom: BorderSide(
                                          color: settingsBorderColor(context),
                                          width: 0.7)),
                            ),
                            child: Row(children: [
                              AvatarView(
                                  width: 44,
                                  height: 44,
                                  text: info.nickname ?? info.userID,
                                  url: info.faceURL),
                              const SizedBox(width: AppTokens.s4),
                              Expanded(
                                  child: Text(
                                      info.nickname?.isNotEmpty == true
                                          ? info.nickname!
                                          : info.userID ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: settingsTextColor(context),
                                          fontSize:
                                              AppTokens.listTitleFontSize))),
                              TextButton(
                                  onPressed: logic.removing.contains(
                                          BlacklistLogic.blockedUserID(info))
                                      ? null
                                      : () => _remove(context, info),
                                  child: Text(text(
                                      context,
                                      logic.removing.contains(
                                              BlacklistLogic.blockedUserID(
                                                  info))
                                          ? '移除中'
                                          : '移除',
                                      logic.removing.contains(
                                              BlacklistLogic.blockedUserID(
                                                  info))
                                          ? 'Removing'
                                          : 'Remove'))),
                            ])),
                    ]),
                  ]));
        }),
        children: const [],
      );
}
