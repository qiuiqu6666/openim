import 'package:flutter/material.dart';

import '../settings_draft_store.dart';
import '../settings_navigation.dart';
import '../settings_service.dart';
import '../widgets/settings_widgets.dart';
import 'moments_privacy_friend_list_page.dart';

class MomentsPermissionPage extends StatelessWidget {
  const MomentsPermissionPage({
    super.key,
    required this.store,
    this.service = const StubSettingsService(),
  });

  final SettingsDraftStore store;
  final SettingsService service;

  String _countLabel(BuildContext context, int count) {
    if (count <= 0) return '';
    return settingsText(context, zh: '$count 人', en: '$count');
  }

  String _rangeLabel(BuildContext context) {
    switch (store.momentsVisibilityDays) {
      case 0:
        return settingsText(context, zh: '全部', en: 'All');
      case 3:
        return settingsText(context, zh: '最近三天', en: 'Last 3 days');
      case 90:
        return settingsText(context, zh: '最近三个月', en: 'Last 3 months');
      case 180:
        return settingsText(context, zh: '最近半年', en: 'Last 6 months');
      case 365:
        return settingsText(context, zh: '最近一年', en: 'Last year');
      default:
        return settingsText(context, zh: '未设置', en: 'Not set');
    }
  }

  Future<void> _pickVisibleRange(BuildContext context) async {
    final current = store.momentsVisibilityDays;
    final options = <int>[0, 3, 90, 180, 365];
    String label(int days) {
      switch (days) {
        case 0:
          return settingsText(context, zh: '全部', en: 'All');
        case 3:
          return settingsText(context, zh: '最近三天', en: 'Last 3 days');
        case 90:
          return settingsText(context, zh: '最近三个月', en: 'Last 3 months');
        case 180:
          return settingsText(context, zh: '最近半年', en: 'Last 6 months');
        case 365:
          return settingsText(context, zh: '最近一年', en: 'Last year');
        default:
          return '$days';
      }
    }

    final selected = await showSettingsActionSheet<int>(
      context,
      title: settingsText(
        context,
        zh: '允许朋友查看朋友圈的范围',
        en: 'Visible Range for Friends',
      ),
      actions: [
        for (final days in options)
          SettingsAction(
            label(days),
            days,
            enabled: current != days,
          ),
      ],
    );
    if (selected == null || selected == current || !context.mounted) return;
    if (!service.isBackendAvailable) {
      await showUnavailableSettingsAction(
        context,
        settingsText(context, zh: '朋友圈隐私设置', en: 'Moments privacy settings'),
      );
      return;
    }
    await service.updateMomentsVisibilityDays(selected);
    if (context.mounted) store.setMomentsVisibilityDays(selected);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: store,
        builder: (context, _) => SettingsScaffold(
          title: settingsText(context, zh: '朋友圈权限', en: 'Moments Privacy'),
          children: [
            SettingsGroup(
              margin: EdgeInsets.zero,
              children: [
                SettingsCell(
                  title: settingsText(
                    context,
                    zh: '不让他(她)看',
                    en: 'Hide My Posts From',
                  ),
                  value: _countLabel(context, store.momentsHiddenFrom.length),
                  onTap: () => openSettingsPage(
                    context,
                    MomentsPrivacyFriendListPage(
                      store: store,
                      kind: MomentsPrivacyListKind.blockedViewer,
                      service: service,
                    ),
                  ),
                ),
                SettingsCell(
                  title: settingsText(
                    context,
                    zh: '不看他（她）',
                    en: 'Hide Their Posts',
                  ),
                  value: _countLabel(context, store.momentsHiddenBy.length),
                  onTap: () => openSettingsPage(
                    context,
                    MomentsPrivacyFriendListPage(
                      store: store,
                      kind: MomentsPrivacyListKind.hiddenAuthor,
                      service: service,
                    ),
                  ),
                ),
                SettingsCell(
                  title: settingsText(
                    context,
                    zh: '允许朋友查看朋友圈的范围',
                    en: 'Visible Range for Friends',
                  ),
                  value: _rangeLabel(context),
                  showDivider: false,
                  onTap: () => _pickVisibleRange(context),
                ),
              ],
            ),
          ],
        ),
      );
}
