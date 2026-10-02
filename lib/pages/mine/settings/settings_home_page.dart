import 'widgets/platform_update.dart';
import 'package:flutter/material.dart';
import 'package:openim_common/openim_common.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'pages/about_us_page.dart';
import 'pages/account_security_page.dart';
import 'pages/display_theme_page.dart';
import 'pages/feedback_page.dart';
import 'pages/friend_permission_page.dart';
import 'pages/moments_permission_page.dart';
import 'pages/node_switch_page.dart';
import 'pages/profile_info_page.dart';
import 'pages/storage_page.dart';
import 'settings_draft_store.dart';
import 'settings_navigation.dart';
import 'settings_service.dart';
import 'widgets/settings_widgets.dart';

class SettingsHomePage extends StatefulWidget {
  const SettingsHomePage({
    super.key,
    required this.store,
    this.service = const StubSettingsService(),
    this.profileName = '',
    this.profileId = '',
    this.avatarUrl = '',
    this.phoneNumber = '',
    this.profileGender = 0,
    this.profileBirth = 0,
    this.onProfileTap,
    this.onLogout,
    this.embedded = false,
  });

  final SettingsDraftStore store;
  final SettingsService service;
  final String profileName;
  final String profileId;
  final String avatarUrl;
  final String phoneNumber;
  final int profileGender;
  final int profileBirth;
  final VoidCallback? onProfileTap;
  final Future<void> Function()? onLogout;
  final bool embedded;

  @override
  State<SettingsHomePage> createState() => _SettingsHomePageState();
}

class _SettingsHomePageState extends State<SettingsHomePage> {
  String _displayVersion = '';
  bool _checkingUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVersion());
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _displayVersion = info.version);
    } catch (_) {
      if (!mounted) return;
      setState(() => _displayVersion = '');
    }
  }

  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      await checkPlatformUpdate(context);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _confirmLogout() async {
    final ok = await showSettingsConfirm(
      context,
      title: settingsText(context, zh: '退出登录', en: 'Log Out'),
      message: settingsText(
        context,
        zh: '确认退出当前账号？',
        en: 'Are you sure you want to log out of this account?',
      ),
      confirmText: settingsText(context, zh: '退出登录', en: 'Log Out'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (widget.onLogout != null) {
      await widget.onLogout!();
      return;
    }
    if (!mounted) return;
    showUnavailableSettingsAction(
      context,
      settingsText(context, zh: '退出登录', en: 'Log Out'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = settingsIsDark(context);
    return SettingsScaffold(
      title: settingsText(context, zh: '设置', en: 'Settings'),
      showLeading: !widget.embedded,
      embedded: widget.embedded,
      children: [
        SettingsGroup(
          children: [
            if (!widget.embedded)
              SettingsCell(
                title: settingsText(context, zh: '个人资料', en: 'Profile'),
                onTap: widget.onProfileTap ??
                    () => openSettingsPage(
                          context,
                          ProfileInfoPage(
                            nickname: widget.profileName,
                            userId: widget.profileId,
                            avatarUrl: widget.avatarUrl,
                            phoneNumber: widget.phoneNumber,
                            gender: widget.profileGender,
                            birth: widget.profileBirth,
                            store: widget.store,
                            service: widget.service,
                          ),
                        ),
              ),
            SettingsCell(
              title: settingsText(context, zh: '账号安全', en: 'Account Security'),
              showDivider: false,
              onTap: () => openSettingsPage(
                context,
                AccountSecurityPage(
                  store: widget.store,
                  service: widget.service,
                  phoneNumber: widget.phoneNumber,
                ),
              ),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsCell(
              title:
                  settingsText(context, zh: '朋友权限', en: 'Friend Permissions'),
              onTap: () => openSettingsPage(
                context,
                FriendPermissionPage(
                    store: widget.store, service: widget.service),
              ),
            ),
            SettingsCell(
              title: settingsText(context, zh: '朋友圈', en: 'Moments'),
              showDivider: false,
              onTap: () => openSettingsPage(
                context,
                MomentsPermissionPage(
                    store: widget.store, service: widget.service),
              ),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsCell(
              title: settingsText(context, zh: '界面与显示', en: 'Appearance'),
              onTap: () => openSettingsPage(
                context,
                DisplayThemePage(store: widget.store),
              ),
            ),
            SettingsCell(
              title: settingsText(context, zh: '储存空间', en: 'Storage'),
              onTap: () => openSettingsPage(
                context,
                StoragePage(service: widget.service),
              ),
            ),
            SettingsCell(
              title: settingsText(context, zh: '节点切换', en: 'Node Switch'),
              showDivider: false,
              onTap: () => openSettingsPage(
                context,
                NodeSwitchPage(store: widget.store, service: widget.service),
              ),
            ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsCell(
              title: settingsText(context, zh: '关于我们', en: 'About Us'),
              onTap: () => openSettingsPage(context, const AboutUsPage()),
            ),
            if (!widget.embedded)
              SettingsCell(
                title: settingsText(context, zh: '意见反馈', en: 'Feedback'),
                onTap: () => openSettingsPage(
                  context,
                  FeedbackPage(service: widget.service),
                ),
              ),
            SettingsCell(
              title: settingsText(context, zh: '当前版本', en: 'Version'),
              value: _displayVersion.isEmpty
                  ? settingsText(context, zh: '获取中', en: 'Loading')
                  : _checkingUpdate
                      ? settingsText(context, zh: '检查中', en: 'Checking')
                      : 'v$_displayVersion',
              showArrow: true,
              showDivider: false,
              onTap: _checkForUpdate,
            ),
          ],
        ),
        if (!widget.embedded)
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 24),
            child: Material(
              color: AppTokens.surface(dark: dark),
              borderRadius: BorderRadius.circular(AppTokens.rLg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _confirmLogout,
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: Text(
                      settingsText(context, zh: '退出登录', en: 'Log Out'),
                      style: const TextStyle(
                        color: AppTokens.walletDanger,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
