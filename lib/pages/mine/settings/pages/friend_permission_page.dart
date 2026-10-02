import '../../../../routes/app_navigator.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';

import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'add_friend_privacy_page.dart';

class FriendPermissionPage extends StatelessWidget {
  const FriendPermissionPage({
    super.key,
    required this.store,
    this.service = const StubSettingsService(),
  });

  final SettingsDraftStore store;
  final SettingsService service;

  String _friendMode(BuildContext context) => store.requireFriendVerification
      ? settingsText(context, zh: '需要验证信息', en: 'Require Verification')
      : settingsText(context, zh: '允许任何人', en: 'Allow Anyone');

  String _lastSeenLabel(BuildContext context, String value) {
    switch (value) {
      case 'friends':
        return settingsText(context, zh: '仅好友可查看', en: 'Friends only');
      case 'none':
        return settingsText(context, zh: '不显示在线时间', en: 'Hidden');
      default:
        return settingsText(context, zh: '所有人可查看', en: 'Everyone');
    }
  }

  Future<void> _chooseFriendMode(BuildContext context) async {
    final current = store.requireFriendVerification;
    final selected = await showSettingsActionSheet<bool>(
      context,
      title: settingsText(context, zh: '谁可以加我为好友', en: 'Who Can Add Me'),
      actions: [
        SettingsAction(
          settingsText(context, zh: '允许任何人', en: 'Allow Anyone'),
          false,
          enabled: current,
        ),
        SettingsAction(
          settingsText(context, zh: '需要验证信息', en: 'Require Verification'),
          true,
          enabled: !current,
        ),
      ],
    );
    if (selected == null) return;
    if (!service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '加我为好友的方式', en: 'Friend request policy'),
      );
      return;
    }
    await service.updateFriendVerification(selected);
    store.setRequireFriendVerification(selected);
  }

  Future<void> _chooseLastSeen(BuildContext context) async {
    final current = store.lastSeenScope;
    final selected = await showSettingsActionSheet<String>(
      context,
      title: settingsText(context, zh: '最后上线时间', en: 'Last Online Time'),
      actions: [
        SettingsAction(
          _lastSeenLabel(context, 'all'),
          'all',
          enabled: current != 'all',
        ),
        SettingsAction(
          _lastSeenLabel(context, 'friends'),
          'friends',
          enabled: current != 'friends',
        ),
        SettingsAction(
          _lastSeenLabel(context, 'none'),
          'none',
          enabled: current != 'none',
        ),
      ],
    );
    if (selected == null) return;
    if (!service.isBackendAvailable) {
      showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '最后上线时间', en: 'Last online time'),
      );
      return;
    }
    await service.updateLastSeenScope(selected);
    store.setLastSeenScope(selected);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final dark = settingsIsDark(context);
          final helperColor = settingsSecondaryTextColor(context);
          return SettingsScaffold(
            title: settingsText(context, zh: '朋友权限', en: 'Friend Permissions'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  settingsText(
                    context,
                    zh: '管理谁可以加你为好友，以及他人通过哪些方式可以找到你。',
                    en: 'Manage who can add you as a friend and how others can find you.',
                  ),
                  style: TextStyle(
                    color: helperColor,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ),
              SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  SettingsCell(
                    title: settingsText(
                      context,
                      zh: '加我为好友的方式',
                      en: 'How Others Can Add Me',
                    ),
                    value: _friendMode(context),
                    onTap: () => _chooseFriendMode(context),
                  ),
                  SettingsCell(
                    title: settingsText(
                      context,
                      zh: '添加我的方式',
                      en: 'Ways to Find Me',
                    ),
                    showDivider: false,
                    onTap: () => openSettingsPage(
                      context,
                      AddFriendPrivacyPage(store: store, service: service),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  SettingsCell(
                    title: settingsText(context, zh: '黑名单', en: 'Blacklist'),
                    showDivider: false,
                    onTap: AppNavigator.startBlacklist,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SettingsGroup(
                margin: EdgeInsets.zero,
                children: [
                  SettingsCell(
                    title: settingsText(
                      context,
                      zh: '最后上线时间',
                      en: 'Last Online Time',
                    ),
                    value: _lastSeenLabel(context, store.lastSeenScope),
                    onTap: () => _chooseLastSeen(context),
                  ),
                  _ToggleCell(
                    title: settingsText(
                      context,
                      zh: '显示在线状态',
                      en: 'Show Online Status',
                    ),
                    subtitle: settingsText(
                      context,
                      zh: '关闭后，您将不可以在会话列表和通讯录中看到好友在线或离线的状态提示。',
                      en: 'When off, online/offline status will not appear in chats or contacts.',
                    ),
                    value: store.showOnlineStatus,
                    onChanged: store.setShowOnlineStatus,
                  ),
                  _ToggleCell(
                    title: settingsText(
                      context,
                      zh: '消息阅读状态',
                      en: 'Read Receipts',
                    ),
                    subtitle: settingsText(
                      context,
                      zh: '关闭后，你和对方都无法看到消息是否已读',
                      en: 'When disabled, neither side can see whether messages have been read.',
                    ),
                    value: store.readReceipts,
                    showDivider: false,
                    onChanged: store.setReadReceipts,
                  ),
                ],
              ),
            ],
          );
        },
      );
}

class _ToggleCell extends StatelessWidget {
  const _ToggleCell({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.showDivider = true,
  });

  final String title;
  final String subtitle;
  final bool value;
  final bool showDivider;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(
                bottom: BorderSide(
                  color: AppTokens.border(dark: dark),
                  width: 0.7,
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTokens.textPrimary(dark: dark),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppTokens.textSecondary(dark: dark),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SettingsPlatformSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
